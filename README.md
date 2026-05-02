# NepaliIME

A macOS Input Method (IME) that converts Roman input into Nepali (Devanagari)
script — the desktop equivalent of Google Input Tools for Nepali.

You type `namaste`, see `नमस्ते` as a marked-text candidate, and commit with
Space. The IME learns from your selections and reorders future candidates
based on frequency + recency.

> **Status:** v0.1. Engine, persistence, and IMK plumbing are
> implemented and unit-tested (47/47 green). Ships with a ~150-word
> starter dictionary; a corpus build pipeline (`scripts/corpus/`) builds
> a real ~30k-headword dictionary from AI4Bharat's Aksharantar dataset
> ranked by Nepali Wikipedia frequency, with a hand-curated lemma seed
> (eval: 68/68). A per-user `.pkg` installer (`scripts/make_pkg.sh`)
> can be shared with non-developers — currently unsigned (Tier 1), so
> recipients right-click → Open the first time.

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
| Return | Commit the raw Roman buffer (no conversion) |
| Escape | Cancel composition |
| Tab | Commit candidate #1 |
| Digits 1–9 | Commit candidate at that index |
| Punctuation | Commit candidate #1, then insert punctuation |
| Arrow Up/Down | Move candidate selection |
| Cmd / Ctrl chord | Pass through unchanged |

## Architecture

```
Sources/NepaliIME/         # Thin executable: IMKServer bootstrap
Sources/NepaliIMECore/     # Library: all logic, unit-testable
├── Engine/                # Trie + Ranker + SuggestionEngine actor
├── Persistence/           # DictionaryManager, UserLearner (GRDB), Watcher
├── Controller/            # IMKInputController, state machine, key router
├── UI/                    # NSPanel + SwiftUI candidate window
└── Support/               # Logger, Paths
Tests/NepaliIMECoreTests/  # XCTest suite
BundleResources/           # Info.plist, system_dict.tsv, icons, lproj strings
├── Info.plist             #   InputMethodKit keys + ComponentInputModeDict
├── system_dict.tsv        #   bundled starter dictionary
├── MenuIcon.icns          #   colored Nepal-flag pennant (menu bar + switcher)
├── PaletteIconTemplate.icns  # "ने" character (template, alternate slot)
├── en.lproj/              #   localized display names
└── ne.lproj/              #   Devanagari display names
scripts/
├── bundle.sh              # swift build → .app bundle, ad-hoc signed
├── install.sh             # bundle.sh + cp to ~/Library/Input Methods/
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

47 tests across `Trie`, `Ranker`, `SuggestionEngine`, `DictionaryManager`,
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
