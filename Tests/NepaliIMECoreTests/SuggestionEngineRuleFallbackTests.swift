import XCTest
@testable import NepaliIMECore

final class SuggestionEngineRuleFallbackTests: XCTestCase {

    func testRuleFallbackIsOnlyResultWhenDictEmpty() async {
        let engine = SuggestionEngine(
            dictionary: EmptyDictionary(),
            learner: NoopLearner(),
            fallback: RuleDictionarySource()
        )
        let results = await engine.candidates(for: "dilip")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.output, "दिलिप")
        XCTAssertEqual(results.first?.source, .rule)
    }

    func testRuleFallbackIsAppendedLastWhenDictHasMatches() async {
        var trie = Trie()
        trie.insert(
            key: "dilip",
            value: Candidate(output: "दिलीप", romanInput: "dilip", baseFrequency: 100, source: .system)
        )
        let engine = SuggestionEngine(
            dictionary: TrieDictionary(trie: trie),
            learner: NoopLearner(),
            fallback: RuleDictionarySource()
        )
        let results = await engine.candidates(for: "dilip")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.output, "दिलीप")     // dict candidate ranks first
        XCTAssertEqual(results.first?.source, .system)
        XCTAssertEqual(results.last?.output, "दिलिप")      // rule candidate appended last
        XCTAssertEqual(results.last?.source, .rule)
    }

    func testRuleFallbackSuppressedWhenDictAlreadyHasSameOutput() async {
        // Rule transliterator produces "नम" for input "nam"; dict also has "नम".
        // Engine should dedupe — only one "नम" candidate, and it should be the
        // dict one (so .system, not .rule).
        var trie = Trie()
        trie.insert(
            key: "nam",
            value: Candidate(output: "नम", romanInput: "nam", baseFrequency: 50, source: .system)
        )
        let engine = SuggestionEngine(
            dictionary: TrieDictionary(trie: trie),
            learner: NoopLearner(),
            fallback: RuleDictionarySource()
        )
        let results = await engine.candidates(for: "nam")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.source, .system)
    }

    func testNoFallbackWhenNotInjected() async {
        // Backwards-compatibility: engine without fallback behaves as before
        // (no rule candidate ever appears).
        let engine = SuggestionEngine(
            dictionary: EmptyDictionary(),
            learner: NoopLearner()
        )
        let results = await engine.candidates(for: "dilip")
        XCTAssertTrue(results.isEmpty)
    }

    func testRuleFallbackRespectsLimit() async {
        // Dict already produces `limit` results — fallback should NOT push
        // the count over the limit.
        let pairs: [(String, String, Int)] = (0..<9).map { i in
            ("dil", "द\(i)", 100 - i)
        }
        var trie = Trie()
        for (input, output, freq) in pairs {
            trie.insert(
                key: input,
                value: Candidate(output: output, romanInput: input, baseFrequency: freq, source: .system)
            )
        }
        let engine = SuggestionEngine(
            dictionary: TrieDictionary(trie: trie),
            learner: NoopLearner(),
            fallback: RuleDictionarySource()
        )
        let results = await engine.candidates(for: "dil", limit: 9)
        XCTAssertEqual(results.count, 9)
        // None of the results should be the rule candidate "दिल" since
        // we filled the limit with dict matches first.
        XCTAssertFalse(results.contains(where: { $0.source == .rule }))
    }
}

// MARK: - Test fixtures

private struct EmptyDictionary: DictionarySource {
    func candidates(for prefix: String) -> [Candidate] { [] }
}

private struct TrieDictionary: DictionarySource {
    let trie: Trie
    func candidates(for prefix: String) -> [Candidate] {
        trie.lookup(prefix: prefix)
    }
}

private struct NoopLearner: LearnerSource {
    func boostScores(for input: String) async -> [String: BoostScore] { [:] }
    func record(input: String, output: String, source: Candidate.Source) async {}
}
