import Foundation

public struct Trie: Sendable, Codable {
    private var root = Node()

    public init() {}

    public mutating func insert(key: String, value: Candidate) {
        guard !key.isEmpty else { return }
        root.insert(chars: Array(key), index: 0, value: value)
    }

    public func lookup(prefix: String) -> [Candidate] {
        guard !prefix.isEmpty else { return [] }
        guard let node = root.find(chars: Array(prefix), index: 0) else { return [] }
        var collected: [Candidate] = []
        node.collect(into: &collected)
        return collected
    }

    private final class Node: Codable, @unchecked Sendable {
        var children: [Character: Node] = [:]
        var values: [Candidate] = []

        init() {}

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

        enum CodingKeys: String, CodingKey { case c, v }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.values = try container.decodeIfPresent([Candidate].self, forKey: .v) ?? []
            let raw = try container.decodeIfPresent([String: Node].self, forKey: .c) ?? [:]
            self.children = Dictionary(uniqueKeysWithValues: raw.compactMap { key, val in
                key.first.map { ($0, val) }
            })
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !values.isEmpty {
                try container.encode(values, forKey: .v)
            }
            if !children.isEmpty {
                let raw = Dictionary(uniqueKeysWithValues: children.map { (String($0.key), $0.value) })
                try container.encode(raw, forKey: .c)
            }
        }
    }
}
