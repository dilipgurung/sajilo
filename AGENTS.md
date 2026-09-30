# AGENTS.md — NepaliIME developer & coding-agent guide

NepaliIME is a macOS InputMethodKit IME that converts Roman input into Nepali
(Devanagari). You type `namaste`, the candidate window shows `नमस्ते`, and
Space commits it. The IME learns from selections and reorders future
candidates by frequency + recency. End-user docs live in `README.md`; this
file holds everything technical.

## Contents

1. [Overview and layout](#overview-and-layout)
2. [Build, test, install, package](#build-test-install-package)
3. [Debugging](#debugging)
4. [Behaviour spec](#behaviour-spec)
5. [Ranking](#ranking)
6. [Dictionaries](#dictionaries)
7. [Icons](#icons)
8. [Conventions for coding agents](#conventions-for-coding-agents)
9. [Known limitations](#known-limitations)

## Overview and layout

Requirements: macOS 14+, Xcode 16+ / Swift 6.0+ toolchain (verified against
Swift 6.3.1). Builds are ad-hoc signed, not notarized.

```
Sources/NepaliIME/         # Thin executable: IMKServer bootstrap
Sources/NepaliIMECore/     # Library: all logic, unit-testable
├── Engine/                # Trie + Ranker + SuggestionEngine actor
│                          # + RuleTransliterator + RuleDictionarySource
├── Persistence/           # DictionaryManager, UserLearner (GRDB), Watcher
├── Controller/            # IMKInputController, state machine, key router
├── UI/                    # NSPanel + SwiftUI candidate window
└── Support/               # Logger, Paths
Tests/NepaliIMECoreTests/  # XCTest suite
BundleResources/           # Info.plist, system_dict.tsv, icons, lproj strings
├── Info.plist             #   InputMethodKit keys + ComponentInputModeDict
├── system_dict.tsv        #   bundled dictionary (~30k headwords, generated)
├── MenuIcon.icns          #   colored Nepal-flag pennant (menu bar + switcher)
├── PaletteIconTemplate.icns  # "ने" character (template, alternate slot)
├── en.lproj/              #   localized display names
└── ne.lproj/              #   Devanagari display names
scripts/
├── bundle.sh              # swift build → .app bundle, ad-hoc signed
├── install.sh             # bundle.sh + cp to ~/Library/Input Methods/
├── uninstall.sh           # remove the .app and (optionally) user data
├── make_pkg.sh            # bundle.sh + pkgbuild + productbuild → .pkg
├── make_icon.swift        # regenerate MenuIcon.icns + PaletteIcon.icns
├── corpus/                # Python pipeline to regenerate system_dict.tsv
│                          # from Aksharantar + Wikipedia + lemma seed
└── pkg_resources/         # Distribution.xml, postinstall, welcome/
                           # conclusion HTML for the .pkg installer
```

Key design choices:

- **Engine is an `actor`**, lookups are `async`. The `IMKInputController` is
  on the main actor (via `MainActor.assumeIsolated` because IMK overrides
  inherit non-isolation regardless of decoration). Lookups are tagged with
  a token so fast typing cancels stale results.
- **Three ranked sources**: bundled system dict, user dict, learned
  selections (see [Ranking](#ranking)).
- **Rule transliterator fallback**: a rule-based Roman → Devanagari layer
  adds candidates for novel words not in the dictionary (`dilip` → दिलिप).
- **In-memory Trie** for the bundled dict, parsed from the TSV on first
  activation (~130 ms in release). There is deliberately no on-disk cache:
  decoding a serialized trie measured ~4× slower than parsing the TSV.
- **GRDB** wraps SQLite for the learner. Writes go through a single
  `DatabaseQueue` inside the `UserLearner` actor.
- **Custom `NSPanel`** (non-activating, hit-testing disabled) hosting a
  SwiftUI candidate list. `IMKCandidates` was rejected as too restrictive.
- While typing, the marked text in the editor stays as the raw Roman
  characters; the Devanagari renderings appear in the candidate window
  (dictionary matches first, rule-transliterated fallback when there's room).

## Build, test, install, package

```bash
swift test                          # run the unit-test suite
./scripts/install.sh                # build, bundle, install to ~/Library/Input Methods/, restart input agents
./scripts/bundle.sh                 # bundle only → dist/NepaliIME.app
./scripts/make_pkg.sh               # → dist/NepaliIME.pkg (unsigned)
./scripts/uninstall.sh              # interactive — asks before deleting user data
./scripts/uninstall.sh --keep-data  # remove the .app, preserve user dict + learner DB
./scripts/uninstall.sh --all        # remove everything without prompting
```

Notes:

- `bundle.sh` builds a **universal binary (arm64 + x86_64)**.
- `install.sh` and the `.pkg` postinstall **kill the running NepaliIME
  process** so the freshly installed binary is picked up. The postinstall
  also pokes `TextInputMenuAgent` so macOS rescans input sources.
- After the first install, enable the input source: System Settings →
  Keyboard → Text Input → Edit → + → "Nepali" → Nepali IME.
- `bundle.sh` (which `make_pkg.sh` invokes) **refuses to ship a bundle whose
  `system_dict.tsv` has < 5,000 data rows** (i.e. looks like a starter dict).
  Set `NEPALI_IME_ALLOW_STARTER=1` to deliberately build a starter-only
  bundle for testing.
- The `.pkg` stages the .app under `Library/Input Methods/` and wraps it
  with `pkgbuild` + `productbuild`; UI screens come from
  `scripts/pkg_resources/`. Output is per-user only (no sudo). It is
  unsigned (see [Known limitations](#known-limitations)).
- `uninstall.sh` removes `~/Library/Input Methods/NepaliIME.app`, kills any
  running instance, restarts the input agents, and (with confirmation)
  wipes `~/Library/Application Support/NepaliIME/` (`user_dict.tsv`,
  `learner.sqlite`). The stale "Nepali IME" entry in System
  Settings → Input Sources must then be removed manually with `−`.
- The packaged `.app` includes `system_dict.tsv` (corpus-built, seed already
  merged in with boosted frequencies) and a copy of
  `scripts/corpus/lemma_seed.tsv` under `Contents/Resources/`. The seed file
  is a transparency artifact — not loaded at runtime.

Canonical sequence for a redistributable package with a refreshed dictionary:

```bash
./scripts/corpus/run_all.sh   # rebuild the ~30k dictionary into BundleResources/
./scripts/make_pkg.sh         # → dist/NepaliIME.pkg
```

## Debugging

Open Console.app and filter by subsystem
`com.gurungdilip.inputmethod.NepaliIME`. Categories: `controller`, `engine`,
`learner`, `panel`, `dict`, `lifecycle`. You generally cannot attach a
debugger to an IME process — the system spawns it — so `os_log` is the
primary diagnostic channel.

## Behaviour spec

Keep this section in sync with the code.

### Composition keys

| Key | Action |
|---|---|
| Latin letters | Insert into the buffer at the caret; refresh candidates |
| Backspace | Delete the character before the caret (exit composition if the buffer empties; no-op with the caret at the start) |
| Space | Commit the highlighted candidate, then insert a literal space |
| Return | Commit the highlighted candidate; caret stays at end of word (no newline inserted) |
| Shift+Return | Commit the raw Roman buffer as typed (no conversion) |
| Escape | Cancel composition |
| Tab | Commit candidate #1 |
| Digits 1–9 | Commit candidate at that index |
| Punctuation | Commit the *highlighted* candidate (not necessarily #1), then insert the punctuation |
| Arrow Up/Down | Move candidate selection |
| Arrow Left/Right | Move the caret within the Roman buffer (clamped to its ends); never commits |
| Cmd / Ctrl chord | Pass through unchanged |
| Caps Lock on | English mode, see below |

### Caps Lock: English mode

Devanagari has no case, and retroflex is Shift+letter (on macOS Shift still
gives a capital with Caps Lock on), so Caps Lock is free to mean "type
English", as it does for CJK input methods.

With Caps Lock on:

- Letters pass through as typed; no composition, no candidate window.
  If a word was being composed, the highlighted candidate is committed first
  and the letter is inserted after it.
- In idle, digits stay ASCII, `.` stays a period, and `\` / `*` stay literal.
- A composition started before Caps Lock went on can still be finished:
  Space, Return, Tab, 1–9, arrows, Backspace and Esc behave as usual.

macOS also has a "Use Caps Lock to switch to and from ABC" setting. When it
is on, Caps Lock is expected to switch input sources instead (not yet
verified with NepaliIME).

Code: `KeyEventRouter.isEnglishMode` and the idle branch of
`InputController.handleOnMain`.

### Period-to-danda auto-conversion

When the caret is **right after** a Devanagari character — or **at most one
space past it** — typing `.` is converted to `।`. The decision is made by
reading the document directly, so it works for any Devanagari in the editor
(freshly typed, typed earlier, or pasted).

- `dilip.` → `दिलिप।` (the mid-composition `.` path also converts)
- `namaste<Space>.` → `नमस्ते ।` (one space — still in range)
- `namaste<Space><Space>.` → `नमस्ते  .` (two spaces — out of range)
- Caret at end of existing `नमस्ते`, type `.` → `नमस्ते।`
- `namaste<Space>hi.` → `नमस्ते hi.` (caret after Latin, period literal)

A second `.` typed immediately after an auto-danda stays literal (`..` →
`।.`): a danda before the caret counts as already-terminated. Backspacing the
danda and retyping `.` converts again because the rule re-reads the document.

In apps that don't fully implement the IMK text-reading APIs (Electron, some
Java) the IME can't see around the caret, so periods always pass through
literally.

### Devanagari digits

While the Nepali IME is the active input source, ASCII digits typed in idle
become `०१२३४५६७८९`. For ASCII digits, turn on Caps Lock (English mode).

- `123` → `१२३`
- `namaste<Tab>123` → `नमस्ते१२३`
- `123abc 456` → `१२३abc ४५६`

Mid-composition, digits 1–9 keep their candidate-selection role (`namaste1`
commits the first candidate); digit `0` mid-composition converts to `०`.

### Idle `\` and `*`

For words already committed (or pasted), with the caret right after a
Devanagari character in idle, `\` inserts a halant and `*` inserts an
anusvara. Chandrabindu in idle isn't supported (it's a two-keystroke
sequence); type the word from scratch with `**` instead.

### Rule transliterator: multi-candidate branching

Roman is ambiguous against Devanagari, so the rule layer emits up to 4
alternative parses when the grammar can plausibly read the same letters more
than one way. The default (longest-match) reading ranks first.

- **Single `a` after a consonant before more input** — inherent schwa
  (default) or long-aa matra (alternative):
  - `gai` → गै (ai diphthong, default) | गाइ (ga + i)
  - `gaee` → गई (ga + ī, default) | गाई (gā + ī)
  - `ram` → रम (default) | राम (long-aa) | रां (anusvara)
- **Trailing `n` or `m` at end of buffer after a vowel matra** — consonant
  with inherent schwa (default) or anusvara on the previous syllable:
  - `gain` → गैन (default) | गैं (anusvara)
  - `naam` → नाम (default) | नां (anusvara)
- **`ri`** → ऋ / ृ only at word start or after a consonant. After a vowel
  (e.g. `hari`) it is र + ि → हरि. After a consonant the split reading is
  also offered as an alternative (`pri` → प्रि).
- **`ng`** → ङ by default, keeping the `g` as its own consonant before more
  input (`sangeet` → सङ्गीत, `sangh` → सङ्घ); at word end both letters fold
  into ङ (`rang` → रङ). Plain न is the alternative (सन्गीत).
- **`ny`** → न्य by default (`anya` → अन्य); ञ is the alternative (अञ).

Committing an alternative teaches the learner, so the preferred reading is
top of the list next time.

### Romanization

The user-facing mapping (vowels, consonants, capital-letter retroflex,
`\` `*` `**`, and the rarer `ri` `rri` `rree` `ng` `ny` `om` `yna`) lives in the README's
[Typing guide](README.md#typing-guide), which is the single source for it.
Keep it in sync with `Engine/RuleTransliterator.swift`. This section only
covers what the README leaves out.

Aliases not in the README: `ii` = `ee` (ई), `uu` = `oo` (ऊ), `c` / `q` = `k`
(क), `z` = `j` (ज). Consonants the README calls "obvious": `k g j t d n p b
m y r l s h` → क ग ज त द न प ब म य र ल स ह.

Capitals follow the ITRANS convention. `T Th D Dh N S Sh` are retroflex and also
emit the dental reading as an alternative, so `Dilip` offers डिलिप then
दिलिप. Other capitals (`K`, `M`, `P`, …) have no retroflex pair: they fall back
to the lowercase reading with no alternatives.

A single final `a` is the inherent schwa, so a final ा needs `aa`. `Tika` →
टिक, `Tikaa` → टिका, `Teekaa` → टीका.

Rule-layer examples (dictionary words rank above these, but at least one rule
reading, two when the input has capitals, always gets a slot):
- `miThaai` → मिठाइ (with मिथाइ also offered).
- `daakTar` → दाक्टर (with दाक्तर alternative).

Word-start specials: `om` → ॐ fires whenever the buffer *starts* with `om`
(`omkaar` → ॐकार by default, ओम्कार as an alternative). `ri` / `rri` /
`rree` are vocalic only at word start or after a consonant, so `harri` →
हर्रि. `yna` (ञ) is the only token with a split alternative (य्न).

Adjacent consonants automatically get a halant between them (`gar` → गर,
`garchha` → गर्छ). The final consonant keeps its inherent schwa (Nepali
convention — `dilip` → दिलिप, not दिलिप्). Digits and punctuation pass
through unchanged (`dilip3` → दिलिप3).

### Forgiving learner normalization

When you commit a word, the learner stores the literal Roman typed
(`gai*DaakoT`) AND a normalized form (`gaidakot`). Lookups query by the
normalized form, so an easier spelling finds an earlier selection.
Normalization:

- Strip the `\` and `*` sigils.
- Lowercase capital letters (retroflex `T/D/N/S/Th/Dh` collapse to dental keys).
- Collapse repeated identical vowels (`aa→a`, `ee→e`, …).

Type `gai*DaakoT` once and commit गैंडाकोट; next time typing `gaidakot`
surfaces it (ranked alongside dictionary completions rather than in the exact tier, since the literal input differs). The literal `input` column still records exactly what
was typed.

## Ranking

Candidates are sorted in **tiers**:

1. **Exact** — the dictionary key equals the typed input (case-insensitive),
   OR the user picked this output for this *literal* input (case-insensitive)
   recently: decayed uses ≥ 0.5, i.e. one pick stays exact for 21 days, two
   picks for 42, and so on.
2. **Everything else** — prefix completions, stale picks, and picks that only
   matched through the learner's normalized key (a pick for `maa` still
   boosts मा when typing `ma`, but never above the exact match म).

Within a tier, candidates are ordered by

```
score = baseFrequency + α · uses · exp(−λ · ageDays)
```

with `α = 100,000` (≈ the top system frequency, so one recent pick promotes a
word to the top) and `λ = ln2/21d` (half-life 21 days). Ties break on output
so ordering is deterministic. The learner is always consulted.

Dictionary keys are stored and queried lowercase (capitals only matter to the
rule layer). Prefix lookups return all exact matches plus the top 32
completions by frequency per dictionary.

Rule-transliterated candidates come after the ranked list. When the window
(9) is full, the rule layer still gets one slot — two if the input contains
capitals, which ask for a retroflex reading — displacing prefix completions
but never exact matches.

Code: `Engine/Ranker.swift`, `Engine/SuggestionEngine.swift`,
`Persistence/DictionaryManager.swift`.

## Dictionaries

### System dictionary (bundled, read-only, generated)

`BundleResources/system_dict.tsv`:

```
roman_input<TAB>devanagari_output<TAB>frequency
```

- Lines starting with `#` are comments.
- The frequency column is optional; defaults to `1`.
- Multiple Roman spellings can map to the same output (`namaste`, `namastey`,
  `nmste` → `नमस्ते`). The Ranker dedupes by output.
- Outputs are NFC-normalised at load time.

This file is **generated** by the corpus pipeline — do not hand-edit it.

### User dictionary (live-editable)

`~/Library/Application Support/NepaliIME/user_dict.tsv`, same format. Edits
are picked up automatically by a `DispatchSource` file watcher (no restart).
When the frequency column is omitted the default is **200,000**, above any
system entry, so user entries outrank system suggestions. Open it from the
IME menu: **Open User Dictionary…**.

Ways to add a word the IME doesn't know:

| Scope | Where | Reload | Use when |
|---|---|---|---|
| Just-typed word | nothing — commit the rule candidate | Instant (learner) | Rule output is correct; occasional word |
| Your machine | `user_dict.tsv` | Live (file watcher) | Reused words; fixing wrong rule output (e.g. `nepal` → नेपल should be नेपाल) |
| Every install | `scripts/corpus/lemma_seed.tsv` | `build_dict.py` + `install.sh` | Words that should ship in the bundle |

### Learned selections

SQLite at `~/Library/Application Support/NepaliIME/learner.sqlite`. Schema:
`(input, normalized_input, output, frequency, last_used, source)` per unique
pair; each commit increments `frequency` and refreshes `last_used`. To reset
learning, delete the file.

### Corpus pipeline

`scripts/corpus/` regenerates `system_dict.tsv` from three sources:

1. **AI4Bharat Aksharantar** (~2.4M Nepali pairs, CC0 + CC-BY) —
   romanizations for inflected/conjugated forms.
2. **Nepali Wikipedia frequency list** (CC-BY-SA) — ranks which Devanagari
   headwords ship.
3. **`scripts/corpus/lemma_seed.tsv`** (hand-curated, ~670 entries) —
   backfills bare lemmas (नेपाल, छ, हो, verb conjugations, numbers,
   days/months, greetings, common ट/ठ/ड/ढ/ण words) that Aksharantar lacks.

```bash
./scripts/corpus/run_all.sh              # one-shot: venv + all 4 steps + eval (~10 min, ~700MB cache)
./scripts/corpus/run_all.sh --top 500    # smoke test; eval ~16/68 is expected
./scripts/install.sh                     # then rebuild + reinstall
```

Expected end state: `system_dict.tsv` ≈ 30k rows across ~29k unique
headwords; eval reports 68/68. Individual steps (idempotent, cached under
`work/corpus/`):

```bash
.venv-corpus/bin/python scripts/corpus/fetch_wiki_freq.py    # → work/corpus/frequencies.tsv
.venv-corpus/bin/python scripts/corpus/fetch_aksharantar.py  # → work/corpus/aksharantar_nep.tsv
.venv-corpus/bin/python scripts/corpus/build_dict.py         # → BundleResources/system_dict.tsv
.venv-corpus/bin/python scripts/corpus/eval.py               # regression check
```

Extending the seed: add `roman<TAB>devanagari<TAB>optional_frequency` rows to
`lemma_seed.tsv` (default frequency 100,000, above Wikipedia's top ~38,000, so
seeded lemmas outrank corpus-mined variants; the seed wins on collision and
gets a boost). Then re-run `build_dict.py` and `install.sh`. For multiple
valid Devanagari spellings in `eval_pairs.tsv`, use `|`-separated
alternatives (`buba<TAB>बुवा|बुबा`). `lemma_seed.tsv` is also copied into the
bundle as a transparency artifact.

Full details (sources, licensing, troubleshooting, optional IndicXlit
gap-fill): [`scripts/corpus/README.md`](scripts/corpus/README.md).

## Icons

The bundle ships two icons, both regenerated by `scripts/make_icon.swift`:

- `MenuIcon.icns` — a solid-red Nepal-flag pennant silhouette. Used by the
  menu-bar tray and (via `tsInputModeMenuIconFileKey`) the Ctrl+Space
  input-source switcher. Multi-resolution: 16, 32, 64, 128, 256.
- `PaletteIconTemplate.icns` — a black `ने` character, no badge. Wired via
  `tsInputModePaletteIconFileKey` and `tsInputModeAlternateMenuIconFileKey`.
  The `Template` filename suffix tells AppKit to treat it as a template
  (alpha mask) so macOS can tint it for whichever surface uses it.

Both must be `.icns` — the TIS code path that loads the switcher icon
silently rejects PDF/TIFF and falls back to a generic blue-circle
placeholder. (Menu-bar loading is more permissive and accepts PDF, but
keeping both as `.icns` avoids the divergence.)

To regenerate after editing the script:

```bash
swift scripts/make_icon.swift
./scripts/install.sh
```

After re-installing, **remove and re-add the input source** in System
Settings → Keyboard → Input Sources for macOS to pick up the new files; its
icon cache is otherwise sticky.

## Conventions for coding agents

- Run `swift test` before committing. CI (`.github/workflows/ci.yml`) runs
  `swift test` and `./scripts/bundle.sh` on every PR.
- Add a test for any behaviour change. The IMK controller and the NSPanel are
  not unit tested — verify those manually in TextEdit.
- Keep the [Behaviour spec](#behaviour-spec) and [Ranking](#ranking) sections,
  and the README's Basic keys and Typing guide, in sync with the code.
- Never commit `work/`, `dist/`, `.venv-corpus/`, or `__pycache__`.
- `system_dict.tsv` is generated by the corpus pipeline. To add words, edit
  `scripts/corpus/lemma_seed.tsv` and re-run `build_dict.py` instead of
  hand-editing it.

## Known limitations

- The `.pkg` installer is **unsigned** — works for anyone willing to
  right-click → Open it once, but Gatekeeper blocks plain double-clicks on
  macOS 10.15+. Notarized builds need an Apple Developer Program membership
  ($99/yr) and Developer ID certs; not yet wired up.
- The Ctrl+Space input-source switcher and the menu-bar tray share a single
  icon (`tsInputModeMenuIconFileKey`); per-surface variations are not honoured
  by macOS for third-party IMEs. We ship the colored flag for both. If macOS
  shows a generic blue circle in the switcher, the `.icns` failed to load —
  see [Icons](#icons).
- Caret-rect positioning relies on
  `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`, which a
  few client apps (Electron, some Java) implement poorly. The panel may
  appear at the wrong position, and auto-danda doesn't work there.
- No Preferences window yet (toggle learning, view paths, reset learner).
