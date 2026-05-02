import Foundation

public enum CompositionState: Sendable, Equatable {
    case idle
    case composing(buffer: String, candidates: [Candidate], selectedIndex: Int)

    public var hasBuffer: Bool {
        if case .composing(let b, _, _) = self { return !b.isEmpty }
        return false
    }

    public var buffer: String {
        if case .composing(let b, _, _) = self { return b }
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
