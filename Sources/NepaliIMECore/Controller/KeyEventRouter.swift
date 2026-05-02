import Foundation
import AppKit

public enum KeyAction: Sendable, Equatable {
    case appendChar(Character)
    case backspace
    case commitSelected            // commit, let the originating key char through (Space)
    case commitSelectedAndEat      // commit, swallow the originating key char (Return)
    case cancel
    case selectIndex(Int)
    case moveSelection(Int)
    case commitSelectedThenInsert(String)
    case passThrough
}

public enum KeyEventRouter {
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
            return hasComposition ? .commitSelectedAndEat : .passThrough
        case "\u{1B}":
            return hasComposition ? .cancel : .passThrough
        case "\t":
            return hasComposition ? .selectIndex(0) : .passThrough
        case "\u{F700}":
            return hasComposition ? .moveSelection(-1) : .passThrough
        case "\u{F701}":
            return hasComposition ? .moveSelection(+1) : .passThrough
        case "\u{F702}", "\u{F703}":
            return hasComposition ? .commitSelected : .passThrough
        default: break
        }

        if first.isASCII, first.isLetter {
            return .appendChar(first)
        }

        if hasComposition {
            if let digit = first.wholeNumberValue, (1...9).contains(digit) {
                return .selectIndex(digit - 1)
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
