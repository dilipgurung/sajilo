# NepaliIME

A macOS Input Method (IME) that converts Roman input into Nepali (Devanagari)
script — the desktop equivalent of Google Input Tools for Nepali. Type
`namaste` and get `नमस्ते`. The IME learns from your selections and reorders
future candidates based on what you pick.

## Requirements

- macOS 14 (Sonoma) or newer

## Install

If you've been handed a `NepaliIME.pkg`:

1. **Right-click** the `.pkg` → **Open** (don't double-click — the installer
   is unsigned, so Gatekeeper blocks plain double-clicks). Click **Open** on
   the security dialog and walk through the installer. It installs to
   `~/Library/Input Methods/` — no admin password required.
2. Enable the input source: **System Settings → Keyboard → Text Input →
   Edit → +** → search "Nepali" → **Nepali IME**.
3. Switch to it with **Control + Space** or the input-source menu in the
   menu bar, then type `namaste` in any text field.

## Basic keys

| Key | Action |
|---|---|
| Space | Commit the highlighted candidate, then insert a space |
| Return | Commit the highlighted candidate (no newline) |
| Shift+Return | Commit the typed Roman letters as-is |
| Tab / 1–9 | Commit the first / Nth candidate |
| ↑ ↓ | Move the highlight |
| ← → | Move within the word being typed, to fix a letter |
| Esc | Cancel |
| `.` after Devanagari | Becomes `।` |
| Digits | Become `०`–`९` |

## Typing guide

Common words come from the dictionary, so a rough spelling usually works. The
rules below are for names and new words. If the first suggestion is wrong,
pick another one: the IME remembers it next time.

Vowels (after a consonant they become the matching vowel sign):

| `a` | `aa` | `i` | `ee` | `u` | `oo` | `e` | `ai` | `o` | `au` |
|---|---|---|---|---|---|---|---|---|---|
| अ | आ | इ | ई | उ | ऊ | ए | ऐ | ओ | औ |

A single `a` at the end of a word is the inherent vowel. Type `aa` for ा:
`chhoraa` → छोरा, `Tikaa` → टिका.

Consonants mostly follow the English sound (`k` → क, `b` → ब, `m` → म). The
less obvious ones:

| `ch` | `chh` | `sh` | `ph` / `f` | `v` / `w` | `ksh` | `gy` | `shr` | `x` |
|---|---|---|---|---|---|---|---|---|
| च | छ | श | फ | व | क्ष | ज्ञ | श्र | क्स |

Add `h` for the aspirated form: `kh` → ख, `gh` → घ, `jh` → झ, `th` → थ,
`dh` → ध, `bh` → भ.

**Capitals give the retroflex letters.** Lowercase `t d n s` are dental.

| `T` | `Th` | `D` | `Dh` | `N` | `S` / `Sh` |
|---|---|---|---|---|---|
| ट | ठ | ड | ढ | ण | ष |

`Thulo` → ठुलो, `gaNesh` → गणेश and `riShi` → ऋषि. The lowercase reading is still offered
as an alternative.

Special keys, typed as part of the word:

| Type | Adds | Example |
|---|---|---|
| `\` | ् (halant) | `bas\` → बस् |
| `*` | ं (anusvara) | `man*` → मनं |
| `**` | ँ (chandrabindu) | `kahaa**` → कहाँ |

After a word is already typed, `\` and `*` still add ् and ं to it.

Less common letters:

| Type | Gives | Example |
|---|---|---|
| `ri` | ृ after a consonant, ऋ at the start of a word | `kripaa` → कृपा, `prithvee` → पृथ्वी (after a vowel it stays रि: `hari` → हरि) |
| `rri` | Same as `ri`, for when you want it explicit | `rri` → ऋ |
| `rree` | ॄ / ॠ (long vocalic R) | `rree` → ॠ |
| `ng` | ङ | `sangeet` → सङ्गीत, `rang` → रङ (न्ग is the alternative) |
| `ny` | न्य, with ञ as the alternative | `kanyaa` → कन्या |
| `om` | ॐ at the start of a word | `om` → ॐ (ओम is the alternative) |
| `yna` | ञ | `yna` → ञ (य्न is the alternative) |

## Adding your own words

Choose **Open User Dictionary…** from the IME's input-source menu and add one
line per word, tab-separated:

```
roman<TAB>देवनागरी[<TAB>frequency]
```

Save the file and it reloads immediately — no restart needed.

## Uninstall

Drag `~/Library/Input Methods/NepaliIME.app` to the Trash. Optionally delete
`~/Library/Application Support/NepaliIME/` to remove your user dictionary and
learned data. From a source checkout you can run `./scripts/uninstall.sh`
instead. Afterwards, remove the stale "Nepali IME" entry in System Settings →
Keyboard → Text Input → Edit.

## Building from source / contributing

See [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE) © 2026 Dilip Gurung
