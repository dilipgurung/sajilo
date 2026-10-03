import XCTest
@testable import SajiloCore

final class TrieTests: XCTestCase {
    func testInsertAndExactLookup() {
        var trie = Trie()
        let c = Candidate(output: "नमस्ते", romanInput: "namaste", baseFrequency: 100, source: .system)
        trie.insert(key: "namaste", value: c)

        let results = trie.lookup(prefix: "namaste")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.output, "नमस्ते")
    }

    func testPrefixMatchReturnsAllDescendants() {
        var trie = Trie()
        trie.insert(key: "nam", value: cand("नाम", "nam", 50))
        trie.insert(key: "namaste", value: cand("नमस्ते", "namaste", 100))
        trie.insert(key: "namuna", value: cand("नमुना", "namuna", 30))
        trie.insert(key: "ghar", value: cand("घर", "ghar", 80))

        let results = trie.lookup(prefix: "nam")
        let outputs = Set(results.map(\.output))
        XCTAssertEqual(outputs, ["नाम", "नमस्ते", "नमुना"])
    }

    func testEmptyPrefixReturnsEmpty() {
        var trie = Trie()
        trie.insert(key: "abc", value: cand("xyz", "abc", 1))
        XCTAssertTrue(trie.lookup(prefix: "").isEmpty)
    }

    func testNoMatchReturnsEmpty() {
        var trie = Trie()
        trie.insert(key: "namaste", value: cand("नमस्ते", "namaste", 100))
        XCTAssertTrue(trie.lookup(prefix: "xyz").isEmpty)
    }

    func testMultipleValuesPerKey() {
        var trie = Trie()
        trie.insert(key: "k", value: cand("क", "k", 100))
        trie.insert(key: "k", value: cand("के", "k", 80))
        let results = trie.lookup(prefix: "k")
        let outputs = Set(results.map(\.output))
        XCTAssertEqual(outputs, ["क", "के"])
    }

    func testCopiesHaveValueSemantics() {
        var original = Trie()
        original.insert(key: "nam", value: cand("नाम", "nam", 50))
        var copy = original
        copy.insert(key: "namaste", value: cand("नमस्ते", "namaste", 100))
        XCTAssertEqual(original.lookup(prefix: "nam").count, 1)
        XCTAssertEqual(copy.lookup(prefix: "nam").count, 2)
    }

    func testCompletionLimitKeepsExactAndTopCompletions() {
        var trie = Trie()
        trie.insert(key: "ka", value: cand("क", "ka", 1))
        trie.insert(key: "kaa", value: cand("का", "kaa", 10))
        trie.insert(key: "kam", value: cand("कम", "kam", 30))
        trie.insert(key: "kati", value: cand("कति", "kati", 20))
        let outputs = trie.lookup(prefix: "ka", completionLimit: 2).map(\.output)
        XCTAssertEqual(outputs, ["क", "कम", "कति"])
    }

    func testCompletionOrderIsDeterministicOnFrequencyTies() {
        var trie = Trie()
        for w in ["kz", "ka", "km", "kb", "ky"] {
            trie.insert(key: w, value: cand(w, w, 100))
        }
        XCTAssertEqual(trie.lookup(prefix: "k", completionLimit: 3).map(\.output), ["ka", "kb", "km"])
    }

    private func cand(_ output: String, _ input: String, _ freq: Int) -> Candidate {
        Candidate(output: output, romanInput: input, baseFrequency: freq, source: .system)
    }
}
