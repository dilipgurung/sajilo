# NepaliIME

A macOS Input Method (IME) that converts Roman input into Nepali (Devanagari)
script — the desktop equivalent of Google Input Tools for Nepali.

You type `namaste`, see `नमस्ते` as a marked-text candidate, and commit with
Space. The IME learns from your selections and reorders future candidates
based on frequency + recency.

> **Status:** v0.1. Engine, persistence, and IMK plumbing are
> implemented and unit-tested (93/93 green). Ships with a ~150-word
> starter dictionary; a corpus build pipeline (`scripts/corpus/`) builds
> a real ~30k-headword dictionary from AI4Bharat's Aksharantar dataset
> ranked by Nepali Wikipedia frequency, with a hand-curated lemma seed
> (eval: 68/68). A rule-based transliterator adds a Roman → Devanagari
> fallback candidate so novel words not in the dictionary still produce
> a usable suggestion (`dilip` → दिलिप). The learner now stores both the
> literal Roman the user typed and a normalized form, so retyping the
> simpler spelling later still finds the previously-committed word.
> A per-user `.pkg` installer (`scripts/make_pkg.sh`) can be shared
> with non-developers — currently unsigned (Tier 1), so recipients
> right-click → Open the first time.

---

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16+ / Swift 6.0+ toolchain (verified against Swift 6.3.1)
- Personal/dev install only — ad-hoc signed, not notarized.

## Install (for end-users — from a `.pkg`)

If you've been handed a `NepaliIME.pkg`:

1. **Right-click** the `.pkg` → **Open** (don't double-click — the
   installer is unsigned, so Gatekeeper blocks plain double-clicks
   on macOS 10.15+ with "App is damaged or can't be opened").
2. Click **Open** on the security dialog, then walk through the
   installer. It copies the IME to `~/Library/Input Methods/` —
   no admin password required.
3. After install, follow the on-screen instructions to enable the
   input source: **System Settings → Keyboard → Text Input → Edit
   (Input Sources) → +** → search "Nepali" → **Nepali IME**.
4. Switch to it via the input-source menu (the small flag/globe icon
   in the menu bar, or **Control + Space**), then type `namaste` in
   TextEdit — you should see नमस्ते as a candidate. **Space** commits.

The unsigned warning will go away once we ship a notarized build
(needs Apple Developer Program — currently out of scope).

## Quick start (for developers — building from source)

```bash
# Build, bundle, install to ~/Library/Input Methods/, restart input agents
./scripts/install.sh
```

Then enable the input source as in step 3 above.

If you only want the bundle without installing it:

```bash
./scripts/bundle.sh
# → dist/NepaliIME.app
```

To build a redistributable installer:

```bash
./scripts/make_pkg.sh
# → dist/NepaliIME.pkg  (~2 MB, ad-hoc / unsigned)
```

The `.pkg` runs `bundle.sh`, stages the .app under `Library/Input
Methods/`, and wraps it with `pkgbuild` + `productbuild` plus a
postinstall hook that pokes `TextInputMenuAgent` so macOS rescans
input sources. UI screens come from `scripts/pkg_resources/`. Output
is per-user only (lands in `~/Library/Input Methods/`, no sudo).

## Uninstall

```bash
./scripts/uninstall.sh              # interactive — asks before deleting user data
./scripts/uninstall.sh --keep-data  # remove the .app, preserve user dict + learner DB
./scripts/uninstall.sh --all        # nuke everything without prompting
```

The script removes `~/Library/Input Methods/NepaliIME.app`, kills any
running IME instance, restarts the input agents so System Settings
re-scans, and (with confirmation) wipes
`~/Library/Application Support/NepaliIME/` (which holds
`user_dict.tsv`, `learner.sqlite`, and the trie cache). After it
finishes, open System Settings → Keyboard → Text Input → Edit
(Input Sources) and click `−` on the now-stale "Nepali IME" entry
to fully forget it.

For end-users who installed via the `.pkg` and don't have the repo
checked out: drag `~/Library/Input Methods/NepaliIME.app` to the
Trash, then optionally remove `~/Library/Application Support/NepaliIME/`
to clean up your learned data.

## Build the real dictionary (recommended after first install)

The default bundle ships with only ~150 starter words. The corpus
pipeline produces a ~30k-headword dictionary by combining three sources:

1. **AI4Bharat Aksharantar** (~2.4M Nepali pairs, CC0 + CC-BY) — gives
   romanizations for inflected/conjugated word forms.
2. **Nepali Wikipedia frequency list** (CC-BY-SA) — ranks which
   Devanagari headwords actually ship in the bundle.
3. **`scripts/corpus/lemma_seed.tsv`** (hand-curated, ~250 entries) —
   backfills bare lemmas (नेपाल, छ, हो, common verb conjugations,
   numbers, days/months, greetings) that Aksharantar lacks because it
   was mined from running text without lemmatization. Edit this file
   to add words you find missing during real-world typing.

### Quick start

```bash
# One-shot: venv setup + all 4 steps + eval (~10 min, ~700MB cache)
./scripts/corpus/run_all.sh

# Then rebuild + reinstall the IME with the new dictionary
./scripts/install.sh
```

Expected end-state: `BundleResources/system_dict.tsv` ≈ 30k rows
across ~29k unique Devanagari headwords; eval reports **68/68 pairs
found (100.0%)**.

To produce a redistributable `.pkg` with the real dictionary, the
canonical sequence is:

```bash
./scripts/corpus/run_all.sh   # build the 30k dictionary into BundleResources/
./scripts/make_pkg.sh         # → dist/NepaliIME.pkg
```

`bundle.sh` (which `make_pkg.sh` invokes) refuses to ship a bundle
where `system_dict.tsv` looks like the 150-word starter (< 5,000
data rows). To deliberately build a starter-only bundle for testing,
set `NEPALI_IME_ALLOW_STARTER=1`.

The packaged `.app` includes both `system_dict.tsv` (corpus-built,
seed already merged in with boosted frequencies) and a copy of
`scripts/corpus/lemma_seed.tsv` (the hand-curated seed source) under
`Contents/Resources/`. The seed file is a transparency artifact —
not loaded at runtime, since its content is already in the merged
dictionary, but useful for users who want to see what was hand-
curated or to copy it into their own setup.

### Smoke test before the full run

```bash
./scripts/corpus/run_all.sh --top 500
```

Only processes the top 500 Wikipedia frequencies. Eval will report
~16/68 hits (Wikipedia's top-500 is encyclopedia-skewed and misses
greetings/copulas) — this is expected for a smoke test and confirms
the pipeline plumbing works.

### Individual steps

Each step is idempotent and caches its output under `work/corpus/`,
so re-running is fast unless you delete the cache.

```bash
.venv-corpus/bin/python scripts/corpus/fetch_wiki_freq.py    # → work/corpus/frequencies.tsv
.venv-corpus/bin/python scripts/corpus/fetch_aksharantar.py  # → work/corpus/aksharantar_nep.tsv
.venv-corpus/bin/python scripts/corpus/build_dict.py         # → BundleResources/system_dict.tsv
.venv-corpus/bin/python scripts/corpus/eval.py               # regression check
```

### Extending the lemma seed

If `eval.py` reports a miss for a word you actually use, add it to
`scripts/corpus/lemma_seed.tsv`:

```
# Format: roman<TAB>devanagari<TAB>optional_frequency
your_word	तपाईंको_देवनागरी
```

Default frequency is 100,000 (above Wikipedia's top-frequency words
~38,000) so seeded lemmas always outrank corpus-mined inflected
variants. Then re-run `build_dict.py` (no need to re-fetch sources)
and `install.sh`.

For multiple valid Devanagari spellings of the same Roman input, use
`|`-separated alternatives in `eval_pairs.tsv`:

```
buba	बुवा|बुबा
```

See [`scripts/corpus/README.md`](scripts/corpus/README.md) for full
details (data sources, licensing, troubleshooting, optional IndicXlit
gap-fill for words still missing from the dict).

## Composition behaviour

| Key | Action |
|---|---|
| Latin letters | Append to buffer; refresh candidates |
| Backspace | Trim buffer (or exit composition if empty) |
| Space | Commit selected candidate, then insert literal space |
| Return | Commit selected candidate; caret stays at end of word (no newline inserted) |
| Escape | Cancel composition |
| Tab | Commit candidate #1 |
| Digits 1–9 | Commit candidate at that index |
| Punctuation | Commit candidate #1, then insert punctuation |
| Arrow Up/Down | Move candidate selection |
| Cmd / Ctrl chord | Pass through unchanged |

## Period-to-danda auto-conversion

When the caret is sitting **right after** a Devanagari character — or
at **most one space past it** — typing `.` is converted to `।`, the
Devanagari danda used as the Nepali full stop. The decision is made
by reading the document directly, so it works for *any* Devanagari
in the editor — freshly typed, typed earlier in the session, or even
pasted from elsewhere.

Examples:

- `dilip.` → `दिलिप।` (the `.` mid-composition path also converts)
- `namaste<Space>.` → `नमस्ते ।` (one space — still in range)
- `namaste<Space><Space>.` → `नमस्ते  .` (two spaces — out of range,
  period passes through unchanged)
- Click at end of an existing `नमस्ते` in the document, type `.` →
  `नमस्ते।` (no need for a recent commit)
- `namaste<Space>hi.` → `नमस्ते hi.` (caret is after Latin, period
  stays literal)

A second `.` typed *immediately* after an auto-danda is left literal
(`..` becomes `।.` rather than `।।`) — the rule treats a danda before
the caret as already-terminated and won't double-fire. If you backspace
the danda and retype `.`, it converts again because the rule re-reads
the document.

In a few apps that don't fully implement the IMK text-reading APIs
(Electron, some Java), the IME can't see what's around the caret and
periods always pass through literally — no auto-danda there.

## Devanagari digits

While the Nepali IME is the active input source, ASCII digits `0-9`
typed in idle become their Devanagari equivalents `०१२३४५६७८९`. To
type ASCII digits (phone numbers, codes, mixed-script numerals),
switch input source to ABC for the digits, then switch back.

- `123` → `१२३`
- `namaste<Tab>123` → `नमस्ते१२३`
- `123abc 456` → `१२३abc ४५६` (letters compose normally; digits convert)

Mid-composition, digits 1-9 keep their candidate-selection role
(`namaste1` commits the first candidate); digit `0` mid-composition
also converts to `०`.

While you type, the marked text in your editor stays as the raw
Roman characters (so you always see what you typed). The
**candidate window** is where the Devanagari renderings appear:
dictionary matches first, then a rule-transliterated fallback last
when there's room.

The fallback covers novel words not in the dictionary — type
`dilip` and दिलिप appears as a candidate even though it's not in
the bundled corpus. Pick it with Space (or any of the candidate
shortcuts) and the IME records the selection in the learner, so
the next time you type the same word it appears as a learned
candidate ahead of the rule one.

### Ambiguous Roman → multiple rule candidates

Roman is genuinely ambiguous against Devanagari, so the rule layer
emits up to 4 alternative parses for inputs where the grammar can
plausibly read the same letters more than one way. The default
(longest-match) reading ranks first; the alternatives appear after
it and you pick the one you meant.

Two branching rules:

- **Single `a` after a consonant before more input** can be either
  the inherent schwa (default) or the long-aa matra (alternative):
  - `gai` → गै (ai diphthong, default) | गाइ (ga + i, the cow word)
  - `gaee` → गई (ga + ī, default) | गाई (gā + ī)
  - `ram` → रम (default) | राम (long-aa, the name) | रां (anusvara)

- **Trailing `n` or `m` at end of buffer after a vowel matra** can be
  either the consonant with inherent schwa (default) or anusvara
  (`ं`) on the previous syllable:
  - `gain` → गैन (default) | गैं (anusvara)
  - `naam` → नाम (default) | नां (anusvara)

If you commit one of the alternatives, the learner remembers your
choice, so next time the same Roman input is typed your preferred
reading is at the top of the list.

### Forgiving learned-entry lookup

Once you commit a rule-built or candidate-list word, the learner
stores the literal Roman you typed (`gai*DaakoT`) AND a normalized
form (`gaidakot`). Future lookups query by the normalized form, so
you can type the easier spelling and still get your earlier
selection back. The normalization rule:

- Strip the `\` and `*` sigils.
- Lowercase capital letters (so retroflex `T/D/N/S/Th/Dh` collapse
  to their dental Roman keys).
- Collapse repeated identical vowels (`aa→a`, `ee→e`, etc.).

Example: type `gai*DaakoT` once, commit गैंडाकोट. Next time, just
type `gaidakot` — गैंडाकोट shows up at the top of the candidate
list. The literal `input` column in `learner.sqlite` still records
exactly what you originally typed, so nothing is lost.

### Adding a word the IME doesn't know

Three paths depending on how permanent the addition should be:

| Scope | Where to edit | Reload | Use when |
|---|---|---|---|
| Single word, just-typed | nothing — pick the rule candidate | Instant (learner records it) | Rule output is correct, throwaway / occasional word |
| Permanent for your machine | `~/Library/Application Support/NepaliIME/user_dict.tsv` | Live (file watcher) | Words you'll re-use; corrections to wrong rule output |
| Permanent in the bundle | `scripts/corpus/lemma_seed.tsv` | After `build_dict.py` + `install.sh` | Words that should ship to every install |

**Path 1 — let the learner pick it up.** If the rule transliterator
gets the spelling right (e.g. `dilip` → दिलिप), just commit it.
The learner stores the `(input, output)` pair in
`~/Library/Application Support/NepaliIME/learner.sqlite`. Next time
you type the same Roman input — or any spelling that **normalizes to
the same key** (sigils stripped, lowercased, repeated vowels collapsed)
— the previously-selected Devanagari appears at the top of the
candidate list. So commit `gai*DaakoT → गैंडाकोट` once and later just
typing `gaidakot` finds it. No editing needed.

**Path 2 — edit the user dictionary.** This is the right path when
the rule output is *wrong* (e.g. `nepal` → नेपल should be नेपाल) or
for words you'll keep typing. Open it from the IME's menu:

> input-source menu (the flag in the menu bar) → **Open User Dictionary…**

Add one row per pair, tab-separated:

```
nepal	नेपाल	100000
nmste	नमस्ते	100000
dilip	दिलिप	100000
```

Format is `roman_input<TAB>devanagari_output<TAB>frequency`.
Save the file — the IME's `DispatchSource` file watcher reloads
immediately, no IME restart needed. User-dict entries get a high
default frequency so they outrank both learned selections and the
bundled system dictionary.

**Path 3 — extend the bundled lemma seed.** For words you want
shipped in `system_dict.tsv` so every install has them, edit
`scripts/corpus/lemma_seed.tsv` (same TSV format), then re-run
just the build step (sources are cached) and reinstall:

```bash
.venv-corpus/bin/python scripts/corpus/build_dict.py
./scripts/install.sh
```

If a word here also has an entry in Aksharantar, the seed value
wins on collision and gets a frequency boost so it outranks the
corpus-mined inflected variants.

### Romanization scheme cheat sheet

Lowercase consonants are dental (त/द/न/स). **Capital letters
mark retroflex** — the ITRANS convention — and additionally emit
the dental reading as a multi-candidate alternative so name typing
like `Dilip` still gives दिलिप as a pickable candidate.

| Roman | Devanagari | Roman | Devanagari |
|---|---|---|---|
| `a` | अ | `aa` / `A` | आ |
| `i` | इ | `ee` / `ii` | ई |
| `u` | उ | `oo` / `uu` | ऊ |
| `e` | ए | `ai` | ऐ |
| `o` | ओ | `au` | औ |
| `k` | क | `kh` | ख |
| `g` | ग | `gh` | घ |
| `ch` | च | `chh` | छ |
| `j` | ज | `jh` | झ |
| `t` | त (dental) | `th` | थ |
| `d` | द (dental) | `dh` | ध |
| `n` | न (dental) | `p` | प |
| `ph` / `f` | फ | `b` | ब |
| `bh` | भ | `m` | म |
| `y` | य | `r` | र |
| `l` | ल | `v` / `w` | व |
| `s` | स | `sh` | श |
| `h` | ह | `ksh` | क्ष |
| `gy` | ज्ञ | `shr` | श्र |

**Capital-letter retroflex** (ITRANS-style):

| Roman | Devanagari | Roman | Devanagari |
|---|---|---|---|
| `T` | ट | `Th` | ठ |
| `D` | ड | `Dh` | ढ |
| `N` | ण | `S` | ष |

Examples:
- `Tika` → टिक (use `Teeka` for टीका).
- `miThaai` → मिठाइ (with मिथाइ also in the candidate list).
- `daakTar` → दाक्टर (with दाक्तर alternative).
- `Dilip` → डिलिप is the default reading; दिलिप appears as the
  alternative — pick it once and the learner remembers next time.

Other capital letters (`K`, `M`, `P`, …) have no retroflex pair
and silently fall back to their lowercase reading — no
alternatives, no surprises.

**Special characters** (combining marks and word-start tokens) —
type these *as part of the same composition that produced the word*,
before committing. The candidate window updates after each keystroke.

| Roman | Devanagari | Use |
|---|---|---|
| `\` | ्  (halant) | Suppresses the schwa of the previous consonant — `bas\` → बस् |
| `*` | ं  (anusvara) | Nasalization on the previous akshara — `man*` → मनं |
| `**` | ँ  (chandrabindu) | `kahaa**` → कहाँ |
| `om` | ॐ  (Om) | Only at word start — `om` → ॐ (with ओम as alt) |
| `yna` | ञ  (palatal nasal) | Alt: य्न |
| `rri` | ऋ / ृ (vocalic R) | Alias for `ri` (also produces a split alt) |
| `rree` | ॠ / ॄ (long vocalic R) | Alt: र्री |
| `ksh` | क्ष | Already covered |
| `gy` | ज्ञ | Already covered |

For words you've **already committed** (or pasted), you can also
use `\` and `*` in idle: position the caret right after a Devanagari
character and type `\` to insert a halant or `*` to insert anusvara.
Chandrabindu in idle isn't supported — it's a two-keystroke sequence
that's awkward without a buffer; type the word from scratch with `**`
inside instead.

Adjacent consonants automatically get a halant inserted between
them (`gar` → गर, `garchha` → गर्छ). Final consonant keeps its
inherent schwa (Nepali convention — `dilip` → दिलिप, not दिलिप्).
Digits and punctuation pass through unchanged (`dilip3` → दिलिप3).

## Architecture

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
├── system_dict.tsv        #   bundled dictionary (~30k headwords after corpus run)
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
  selections. Score = `baseFreq + α · userFreq · exp(-λ · ageDays)` with
  `α = 50`, `λ = ln2/21d` (half-life ~21 days).
- **In-memory Trie** for the bundled dict (cached as a binary plist in
  `~/Library/Application Support/NepaliIME/cache/` keyed on TSV size +
  mtime, so cold start avoids re-parsing).
- **GRDB** wraps SQLite for the learner. Writes go through a single
  `DatabaseQueue` inside the `UserLearner` actor.
- **Custom `NSPanel`** (non-activating, hit-testing disabled) hosting a
  SwiftUI candidate list. `IMKCandidates` was rejected as too restrictive.

## Dictionaries

> To regenerate the bundled dictionary from real corpora (Aksharantar +
> Nepali Wikipedia), see [`scripts/corpus/README.md`](scripts/corpus/README.md).
> Output drops into `BundleResources/system_dict.tsv` in the format below.

### System dictionary (bundled, read-only)

`BundleResources/system_dict.tsv`, format:

```
roman_input<TAB>devanagari_output<TAB>frequency
```

- Lines starting with `#` are comments.
- The frequency column is optional; defaults to `1`.
- Multiple Roman spellings can map to the same output — encouraged for
  common transliteration variants (e.g. `namaste`, `namastey`, `nmste` →
  `नमस्ते`). The Trie handles dedupe by output.
- Outputs are NFC-normalised at load time.

### User dictionary (live-editable)

`~/Library/Application Support/NepaliIME/user_dict.tsv`

Same format. Edits are picked up automatically (`DispatchSource`-based
file watcher; no IME restart needed). User-dict entries get a high default
base frequency so they outrank system suggestions.

You can open it from the IME's menu: **input-source menu → Open User Dictionary…**

### Learned selections

SQLite at `~/Library/Application Support/NepaliIME/learner.sqlite`.
Records `(input, output, frequency, last_used, source)` per unique pair;
each commit increments `frequency` and refreshes `last_used`. To reset
learning, delete the file.

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
Settings → Keyboard → Input Sources for macOS to pick up the new files;
its icon cache is otherwise sticky.

## Tests

```bash
swift test
```

93 tests across `Trie`, `Ranker`, `SuggestionEngine`,
`SuggestionEngineRuleFallback`, `RuleTransliterator`, `DictionaryManager`,
`UserLearner`, `KeyEventRouter`, `PanelPositioner`. The IMK controller and
the NSPanel are not unit-tested — IME UX is verified manually in real apps.

## Logs

Open Console.app and filter by subsystem
`com.gurungdilip.inputmethod.NepaliIME`. Categories: `controller`, `engine`,
`learner`, `panel`, `dict`, `lifecycle`. You generally cannot attach a
debugger to an IME process — the system spawns it — so `os_log` is the
primary diagnostic channel.

## Known limitations / not yet implemented

- Starter dictionary is ~150 words. Run `./scripts/corpus/run_all.sh` to
  build a ~30k-headword replacement from Aksharantar + Wikipedia
  (~10 min, ~700MB cache). Pipeline is run-on-demand; the generated
  dictionary is committed alongside the source TSV.
- The Ctrl+Space input-source switcher and the menu-bar tray share a
  single icon (`tsInputModeMenuIconFileKey`); per-surface variations are
  not honoured by macOS for third-party IMEs. We ship the colored flag
  for both. If macOS shows a generic blue circle in the switcher, the
  `.icns` failed to load — see the "Icons" section.
- No Preferences window yet (toggle learning, view paths, reset learner).
- The `.pkg` installer (`scripts/make_pkg.sh`) is **unsigned** — works
  for the developer and anyone willing to right-click → Open it once,
  but Gatekeeper blocks plain double-clicks on macOS 10.15+. Notarized
  builds need an Apple Developer Program membership ($99/yr) and
  Developer ID certs; not yet wired up.
- Caret-rect positioning relies on `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`,
  which a few client apps (Electron, some Java) implement poorly. The panel
  may appear at the wrong position in those apps.

## License

[MIT](LICENSE) © 2026 Dilip Gurung
