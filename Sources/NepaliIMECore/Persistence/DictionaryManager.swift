import Foundation
import os

public final class DictionaryManager: DictionarySource, @unchecked Sendable {
    private let systemDictURL: URL
    private let userDictURL: URL?
    private let cacheURL: URL?
    private let lock = NSLock()
    private var systemTrie: Trie
    private var userTrie: Trie

    private static let userBaseFrequency = 1000

    public init(systemDictURL: URL, userDictURL: URL?, cacheURL: URL? = Paths.systemDictCache) throws {
        self.systemDictURL = systemDictURL
        self.userDictURL = userDictURL
        self.cacheURL = cacheURL
        self.systemTrie = Trie()
        self.userTrie = Trie()
        try loadSystemTrie()
        try reloadUserDictionaryLocked()
    }

    public func candidates(for prefix: String) -> [Candidate] {
        lock.lock()
        defer { lock.unlock() }
        return systemTrie.lookup(prefix: prefix) + userTrie.lookup(prefix: prefix)
    }

    public func reloadUserDictionary() throws {
        lock.lock()
        defer { lock.unlock() }
        try reloadUserDictionaryLocked()
    }

    private func loadSystemTrie() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: systemDictURL.path)
        let size = (attrs[.size] as? UInt64) ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        if let cacheURL, let cached = readCache(at: cacheURL),
           cached.sourceSize == size, abs(cached.sourceMTime - mtime) < 0.001 {
            Log.dict.info("Loaded system dictionary from cache (\(size) bytes)")
            self.systemTrie = cached.trie
            return
        }

        Log.dict.info("Building system dictionary from TSV (\(size) bytes)")
        var trie = Trie()
        var loaded = 0
        var skipped = 0
        try parseTSV(at: systemDictURL) { input, output, freq in
            let baseFreq = freq ?? 1
            let cand = Candidate(
                output: output.precomposedStringWithCanonicalMapping,
                romanInput: input,
                baseFrequency: baseFreq,
                source: .system
            )
            trie.insert(key: input, value: cand)
            loaded += 1
        } onSkip: { _ in skipped += 1 }
        Log.dict.info("System dict: loaded \(loaded), skipped \(skipped)")
        self.systemTrie = trie

        if let cacheURL {
            try? writeCache(at: cacheURL, payload: CachedDictionary(sourceSize: size, sourceMTime: mtime, trie: trie))
        }
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
                baseFrequency: freq ?? Self.userBaseFrequency,
                source: .user
            )
            trie.insert(key: input, value: cand)
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

    private struct CachedDictionary: Codable {
        let sourceSize: UInt64
        let sourceMTime: TimeInterval
        let trie: Trie
    }

    private func readCache(at url: URL) -> CachedDictionary? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(CachedDictionary.self, from: data)
    }

    private func writeCache(at url: URL, payload: CachedDictionary) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
