import Foundation

public struct Trie: Sendable {
    private var root = Node()

    public init() {}

    public mutating func insert(key: String, value: Candidate) {
        guard !key.isEmpty else { return }
        // Nodes are reference types; copy before mutating a shared trie
        // so `Trie` keeps value semantics.
        if !isKnownUniquelyReferenced(&root) { root = root.deepCopy() }
        root.insert(chars: Array(key), index: 0, value: value)
    }

    /// All values stored at `prefix` itself, plus every value in its
    /// subtree (prefix completions).
    public func lookup(prefix: String) -> [Candidate] {
        guard !prefix.isEmpty else { return [] }
        guard let node = root.find(chars: Array(prefix), index: 0) else { return [] }
        var collected: [Candidate] = []
        node.collect(into: &collected)
        return collected
    }

    /// All values stored at `prefix` itself, plus at most
    /// `completionLimit` completions from its subtree, highest
    /// `baseFrequency` first.
    public func lookup(prefix: String, completionLimit: Int) -> [Candidate] {
        guard !prefix.isEmpty else { return [] }
        guard let node = root.find(chars: Array(prefix), index: 0) else { return [] }
        var completions: [Candidate] = []
        for child in node.children.values {
            child.collect(into: &completions)
        }
        if completions.count > completionLimit {
            completions.sort { $0.baseFrequency > $1.baseFrequency }
            completions.removeSubrange(completionLimit...)
        }
        return node.values + completions
    }

    private final class Node: @unchecked Sendable {
        var children: [Character: Node] = [:]
        var values: [Candidate] = []

        init() {}

        func deepCopy() -> Node {
            let copy = Node()
            copy.values = values
            copy.children = children.mapValues { $0.deepCopy() }
            return copy
        }

        func insert(chars: [Character], index: Int, value: Candidate) {
            if index == chars.count {
                values.append(value)
                return
            }
            let child = children[chars[index]] ?? Node()
            child.insert(chars: chars, index: index + 1, value: value)
            children[chars[index]] = child
        }

        func find(chars: [Character], index: Int) -> Node? {
            if index == chars.count { return self }
            guard let child = children[chars[index]] else { return nil }
            return child.find(chars: chars, index: index + 1)
        }

        func collect(into out: inout [Candidate]) {
            out.append(contentsOf: values)
            for child in children.values {
                child.collect(into: &out)
            }
        }
    }
}
