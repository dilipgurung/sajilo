import Foundation
import AppKit

public enum KeyAction: Sendable, Equatable {
    case appendChar(Character)
    case backspace
    case commitSelected            // commit, let the originating key char through (Space)
    case commitSelectedAndEat      // commit, swallow the originating key char (Return)
    case commitRaw                 // commit the Roman buffer as typed (Shift+Return)
    case cancel
    case selectIndex(Int)
    case moveSelection(Int)
    case moveCaret(Int)            // Left/Right within the Roman buffer
    case commitSelectedThenInsert(String)
    case passThrough
}

public enum KeyEventRouter {
    /// Caps Lock turns the IME into an English pass-through: letters (and,
    /// in the controller, idle digits and punctuation) reach the app as
    /// typed. Devanagari has no case, and retroflex is Shift+letter, which
    /// works the same with Caps Lock on or off.
    public static func isEnglishMode(_ modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(.capsLock)
    }

    public static func classify(
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags,
        hasComposition: Bool
    ) -> KeyAction {
        guard let chars = characters, let first = chars.first else { return .passThrough }

        let mods = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let nonShiftMods = mods.subtracting([.shift, .capsLock])
        if nonShiftMods.contains(.command) || nonShiftMods.contains(.control) {
            return .passThrough
        }

        switch first {
        case "\u{8}", "\u{7F}":
            return hasComposition ? .backspace : .passThrough
        case " ":
            return hasComposition ? .commitSelected : .passThrough
        case "\r", "\u{3}":
            // Return commits the currently-selected candidate (matching
            // Space and Tab) and SWALLOWS the newline — caret lands
            // immediately after the committed word, no line break.
            // Falls back to raw-buffer insert internally when no
            // candidates exist (commitSelectedAndReset's empty case).
            // Shift+Return is the escape hatch for Latin text: commit
            // the Roman buffer exactly as typed.
            guard hasComposition else { return .passThrough }
            return mods.contains(.shift) ? .commitRaw : .commitSelectedAndEat
        case "\u{1B}":
            return hasComposition ? .cancel : .passThrough
        case "\t":
            return hasComposition ? .selectIndex(0) : .passThrough
        case "\u{F700}":
            return hasComposition ? .moveSelection(-1) : .passThrough
        case "\u{F701}":
            return hasComposition ? .moveSelection(+1) : .passThrough
        case "\u{F702}":
            // Left/Right edit the word being composed rather than
            // committing it — only Space/Return/Tab/digits commit.
            return hasComposition ? .moveCaret(-1) : .passThrough
        case "\u{F703}":
            return hasComposition ? .moveCaret(+1) : .passThrough
        default: break
        }

        if first.isASCII, first.isLetter {
            if isEnglishMode(mods) {
                // Finish a word started before Caps Lock went on, then
                // let the letter through.
                return hasComposition ? .commitSelectedThenInsert(String(first)) : .passThrough
            }
            return .appendChar(first)
        }

        if hasComposition {
            if let digit = first.wholeNumberValue, (1...9).contains(digit) {
                return .selectIndex(digit - 1)
            }
            // `\` and `*` are special transliteration tokens (halant,
            // anusvara, chandrabindu) — pass them into the buffer so
            // the rule transliterator can fold them into the candidate
            // output. In idle they remain passThrough; the InputController
            // handles direct-insert there.
            if first == "\\" || first == "*" {
                return .appendChar(first)
            }
            if first.isASCII, !first.isLetter, !first.isWhitespace {
                return .commitSelectedThenInsert(String(first))
            }
        }

        return .passThrough
    }

    public static func classify(event: NSEvent, hasComposition: Bool) -> KeyAction {
        // Use `characters` (not `charactersIgnoringModifiers`) so Shift
        // produces the actual cased character — required for the
        // capital-letter retroflex convention (Shift+t → "T" → ट).
        // Special keys (arrows, Tab, Return, Esc, Backspace) come
        // through identically in both, so behaviour for those is
        // unchanged.
        classify(
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            hasComposition: hasComposition
        )
    }
}
