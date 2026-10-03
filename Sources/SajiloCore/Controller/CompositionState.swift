import Foundation

/// The Roman text being composed plus the caret position within it,
/// measured in `Character`s from the start. Left/Right move the caret so
/// the user can fix a typo mid-word; typing and Backspace act at the caret.
public struct CompositionBuffer: Sendable, Equatable {
    public private(set) var text: String
    public private(set) var caret: Int

    public init(text: String = "", caret: Int? = nil) {
        self.text = text
        self.caret = max(0, min(text.count, caret ?? text.count))
    }

    public var isEmpty: Bool { text.isEmpty }

    /// Caret offset in UTF-16 units, as `setMarkedText(selectionRange:)` expects.
    public var caretUTF16Offset: Int {
        String(text.prefix(caret)).utf16.count
    }

    public mutating func insert(_ ch: Character) {
        let idx = text.index(text.startIndex, offsetBy: caret)
        text.insert(ch, at: idx)
        caret += 1
    }

    /// Deletes the character before the caret. No-op at the start.
    public mutating func deleteBackward() {
        guard caret > 0 else { return }
        let idx = text.index(text.startIndex, offsetBy: caret - 1)
        text.remove(at: idx)
        caret -= 1
    }

    /// Moves the caret by `delta` characters, clamped to the buffer.
    public mutating func moveCaret(by delta: Int) {
        caret = max(0, min(text.count, caret + delta))
    }
}

public enum CompositionState: Sendable, Equatable {
    case idle
    case composing(buffer: CompositionBuffer, candidates: [Candidate], selectedIndex: Int)

    public var hasBuffer: Bool {
        if case .composing(let b, _, _) = self { return !b.isEmpty }
        return false
    }

    public var buffer: String {
        if case .composing(let b, _, _) = self { return b.text }
        return ""
    }

    public var candidates: [Candidate] {
        if case .composing(_, let c, _) = self { return c }
        return []
    }

    public var selectedIndex: Int {
        if case .composing(_, _, let i) = self { return i }
        return 0
    }
}
