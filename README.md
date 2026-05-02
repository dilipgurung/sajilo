# NepaliIME

A macOS Input Method (IME) that converts Roman input into Nepali (Devanagari)
script — the desktop equivalent of Google Input Tools for Nepali.

You type `namaste`, see `नमस्ते` as a marked-text candidate, and commit with
Space. The IME learns from your selections and reorders future candidates
based on frequency + recency.

> **Status:** v0.1 scaffold. Engine, persistence, and IMK plumbing are
> implemented and unit-tested (47/47 green). Ships with a ~150-word starter
> dictionary; a real corpus needs to be sourced before this is useful day-to-day.

---

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16+ / Swift 6.0+ toolchain (verified against Swift 6.3.1)
- Personal/dev install only — ad-hoc signed, not notarized.

## Quick start

```bash
# Build, bundle, install to ~/Library/Input Methods/, restart input agents
./scripts/install.sh
```

Then:

1. Open **System Settings → Keyboard → Text Input → Edit (Input Sources)**
2. Click **+**, search "Nepali", pick **Nepali IME**
3. Switch to it via the input-source menu (globe icon, or Ctrl+Space)
4. Type `namaste` in TextEdit — you should see a marked-text underline plus
   a candidate panel below the caret. Press Space to commit candidate #1.

If you only want the bundle without installing it:

```bash
./scripts/bundle.sh
# → dist/NepaliIME.app
```

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
BundleResources/           # Info.plist + system_dict.tsv
scripts/                   # bundle.sh + install.sh
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

- Starter dictionary is ~150 words. Needs a real 20–40k corpus to be
  practically useful.
- No menu-bar icon (`MenuIcon.tiff`) is bundled — will fall back to a
  default placeholder in the input-source menu.
- No Preferences window yet (toggle learning, view paths, reset learner).
- Not notarised. Personal/dev install only.
- Caret-rect positioning relies on `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`,
  which a few client apps (Electron, some Java) implement poorly. The panel
  may appear at the wrong position in those apps.

## License

Personal project, all rights reserved.
