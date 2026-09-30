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
| Esc | Cancel |
| `.` after Devanagari | Becomes `।` |
| Digits | Become `०`–`९` |

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
