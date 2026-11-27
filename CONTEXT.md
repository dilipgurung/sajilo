# Sajilo

Sajilo is a macOS input method for typing Nepali phonetically: the user types
Roman letters and picks a Devanagari word from a list of suggestions. This
glossary fixes the words we use for the product and how users meet it.

## Language

### Naming

**Sajilo**:
The product name (सजिलो, "easy"), as used on GitHub, in the README, the
installer and release files. Tagline: "Sajilo typing for Mac".
_Avoid_: NepaliIME, Nepali IME, Nepali Input Tools

**Input source**:
The entry a user adds in System Settings and then picks from the menu bar or
the Ctrl+Space switcher. Sajilo's input source carries the product name:
"Sajilo" (English), "सजिलो" (Nepali), so the name users see in the menu bar
matches the app they installed. It used to be "Nepali – Phonetic". The
Nepali language grouping in System Settings (`TISIntendedLanguage` = `ne`)
already tells users what it does. Its ID,
`com.gurungdilip.inputmethod.Sajilo.Nepali`, must not change: existing
installs refer to the input source by that ID.
_Avoid_: IME, keyboard, input tool

### Typing

**Phonetic typing**:
Typing Nepali by spelling the sound in Roman letters and choosing among
suggested Devanagari words, as Google Input Tools does.
_Avoid_: Romanized (that word names a different, fixed key-for-key layout), transliteration (as a user-facing term)

**Romanized layout**:
A fixed keyboard layout that puts one Devanagari character on each Roman key,
with no suggestions (e.g. Nepali Romanized Pro).
Sajilo is not a Romanized layout.
