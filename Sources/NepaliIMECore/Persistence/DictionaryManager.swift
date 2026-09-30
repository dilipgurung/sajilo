import Foundation
import os

public final class DictionaryManager: DictionarySource, @unchecked Sendable {
    private let systemDictURL: URL
    private let userDictURL: URL?
    private let lock = NSLock()
    private var systemTrie: Trie
    private var userTrie: Trie
    private let completionLimit: Int

    /// Frequency given to user-dictionary rows that omit the column —
    /// above every system entry (seed lemmas ship at 100,000).
    public static let userDefaultFrequency = 200_000

    /// - Parameter completionLimit: max prefix completions returned per
    ///   dictionary on each lookup; exact matches are always returned.
    public init(
        systemDictURL: URL,
        userDictURL: URL?,
        completionLimit: Int = 32
    ) throws {
        self.systemDictURL = systemDictURL
        self.userDictURL = userDictURL
        self.completionLimit = completionLimit
        self.systemTrie = Trie()
        self.userTrie = Trie()
        try loadSystemTrie()
        try reloadUserDictionaryLocked()
    }

    /// Keys are stored lowercase, so lookup ignores case.
    public func candidates(for prefix: String) -> [Candidate] {
        let prefix = prefix.lowercased()
        lock.lock()
        defer { lock.unlock() }
        return systemTrie.lookup(prefix: prefix, completionLimit: completionLimit)
            + userTrie.lookup(prefix: prefix, completionLimit: completionLimit)
    }

    public func reloadUserDictionary() throws {
        lock.lock()
        defer { lock.unlock() }
        try reloadUserDictionaryLocked()
    }

    // Parsing the TSV (~130 ms for 30k rows in release) is faster than
    // decoding a serialized trie, so there is no on-disk cache.
    private func loadSystemTrie() throws {
        var trie = Trie()
        var loaded = 0
        var skipped = 0
        try parseTSV(at: systemDictURL) { input, output, freq in
            let cand = Candidate(
                output: output.precomposedStringWithCanonicalMapping,
                romanInput: input,
                baseFrequency: freq ?? 1,
                source: .system
            )
            trie.insert(key: input.lowercased(), value: cand)
            loaded += 1
        } onSkip: { _ in skipped += 1 }
        Log.dict.info("System dict: loaded \(loaded), skipped \(skipped)")
        self.systemTrie = trie
    }

    private func reloadUserDictionaryLocked() throws {
        guard let userDictURL else {
            self.userTrie = Trie()
            return
        }
        guard FileManager.default.fileExists(atPath: userDictURL.path) else {
            self.userTrie = Trie()
            return
        }
        var trie = Trie()
        try parseTSV(at: userDictURL) { input, output, freq in
            let cand = Candidate(
                output: output.precomposedStringWithCanonicalMapping,
                romanInput: input,
                baseFrequency: freq ?? Self.userDefaultFrequency,
                source: .user
            )
            trie.insert(key: input.lowercased(), value: cand)
        } onSkip: { _ in }
        self.userTrie = trie
    }

    private func parseTSV(
        at url: URL,
        onRow: (_ input: String, _ output: String, _ freq: Int?) -> Void,
        onSkip: (_ line: String) -> Void
    ) throws {
        let raw = try String(contentsOf: url, encoding: .utf8)
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { onSkip(trimmed); continue }
            let input = parts[0].trimmingCharacters(in: .whitespaces)
            let output = parts[1]
            guard !input.isEmpty, !output.isEmpty else { onSkip(trimmed); continue }
            var freq: Int? = nil
            if parts.count >= 3 {
                let f = parts[2].trimmingCharacters(in: .whitespaces)
                if !f.isEmpty {
                    if let parsed = Int(f) {
                        freq = parsed
                    } else {
                        // Malformed frequency: keep the row but use default
                        Log.dict.warning("Malformed frequency on line, using default: \(trimmed)")
                    }
                }
            }
            onRow(input, output, freq)
        }
    }
}
