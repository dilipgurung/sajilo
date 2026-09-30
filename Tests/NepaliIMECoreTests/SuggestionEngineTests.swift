import XCTest
@testable import NepaliIMECore

final class SuggestionEngineTests: XCTestCase {
    func testReturnsEmptyForEmptyInput() async {
        let engine = makeEngine(dictPairs: [("namaste", "नमस्ते", 100)])
        let results = await engine.candidates(for: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testReturnsExactMatchThenCompletionsByFrequency() async {
        let engine = makeEngine(dictPairs: [
            ("nam", "नाम", 50),
            ("namaste", "नमस्ते", 100),
            ("namuna", "नमुना", 30),
            ("ghar", "घर", 80),
        ])
        let results = await engine.candidates(for: "nam")
        let outputs = results.map(\.output)
        XCTAssertFalse(outputs.contains("घर"))
        XCTAssertEqual(outputs, ["नाम", "नमस्ते", "नमुना"])
    }

    func testLearnedSelectionPromotesCandidate() async {
        let learner = FakeLearner()
        let engine = makeEngine(
            dictPairs: [
                ("nam", "नाम", 200),
                ("nam", "नमक", 50),
            ],
            learner: learner
        )
        let now = Date()
        for _ in 0..<10 {
            await learner.injectBoost(input: "nam", output: "नमक", freq: 1, when: now)
        }
        let results = await engine.candidates(for: "nam")
        XCTAssertEqual(results.first?.output, "नमक")
    }

    func testLimitTruncatesResults() async {
        let pairs: [(String, String, Int)] = (0..<20).map { i in
            ("ka", "क\(i)", 100 - i)
        }
        let engine = makeEngine(dictPairs: pairs)
        let results = await engine.candidates(for: "ka", limit: 5)
        XCTAssertEqual(results.count, 5)
    }

    func testRecordSelectionForwardsToLearner() async {
        let learner = FakeLearner()
        let engine = makeEngine(dictPairs: [("nam", "नाम", 50)], learner: learner)
        await engine.recordSelection(input: "nam", output: "नाम", source: .system)
        let recorded = await learner.recordedCount
        XCTAssertEqual(recorded, 1)
    }

    // MARK: - Learned-only outputs become first-class candidates

    func testLearnedOnlyOutputSurfacesWhenDictHasNoMatch() async {
        // Dict knows nothing about "gaidakot", but the learner has a
        // boost for it from a prior commit. Engine should promote that
        // learned output into the candidate list.
        let learner = FakeLearner()
        let engine = makeEngine(dictPairs: [], learner: learner)
        let now = Date()
        await learner.injectBoost(input: "gaidakot", output: "गैंडाकोट", freq: 3, when: now)
        let results = await engine.candidates(for: "gaidakot")
        XCTAssertEqual(results.first?.output, "गैंडाकोट")
        XCTAssertEqual(results.first?.source, .learned)
    }

    func testLearnedOutputMergesWithDictMatches() async {
        // Dict has one match; learner adds a different output for the
        // same input. Both should appear; the learned one ranks first
        // because the learner boost outweighs the dict's small base freq.
        let learner = FakeLearner()
        let engine = makeEngine(
            dictPairs: [("nam", "नाम", 10)],
            learner: learner
        )
        await learner.injectBoost(input: "nam", output: "नमुना", freq: 100, when: Date())
        let results = await engine.candidates(for: "nam")
        let outputs = results.map(\.output)
        XCTAssertTrue(outputs.contains("नाम"),  "expected dict output नाम in \(outputs)")
        XCTAssertTrue(outputs.contains("नमुना"), "expected learned output नमुना in \(outputs)")
    }

    // MARK: - Learner always consulted / exact-match tier

    func testLearnerReordersEvenWhenDictFillsWindow() async {
        // 20 dict matches fill the 9-slot window; a single recent pick of
        // a lower-ranked completion must still promote it to the top.
        let learner = FakeLearner()
        let pairs: [(String, String, Int)] = (0..<20).map { i in
            ("ma\(i)", "म\(i)", 100_000 - i)
        }
        let engine = makeEngine(dictPairs: pairs, learner: learner, ranker: Ranker())
        await learner.injectBoost(input: "ma", output: "म15", freq: 1, when: Date())
        let results = await engine.candidates(for: "ma", limit: 9)
        XCTAssertEqual(results.first?.output, "म15")
    }

    func testExactMatchRanksAboveHigherFrequencyCompletions() async {
        let engine = makeEngine(dictPairs: [
            ("kati", "कति", 100_000),
            ("karod", "करोड", 100_000),
            ("kaa", "का", 10),
        ])
        let results = await engine.candidates(for: "kaa")
        XCTAssertEqual(results.first?.output, "का")
        let results2 = await engine.candidates(for: "Kaa")
        XCTAssertEqual(results2.first?.output, "का", "exact match is case-insensitive")
    }

    func testNormalizedOnlyLearnedPickDoesNotOutrankExactMatch() async {
        // Picking मा for `maa` stores a boost under the normalized key `ma`.
        // Typing `ma` must still show the exact match म first.
        let learner = FakeLearner()
        let engine = makeEngine(
            dictPairs: [("ma", "म", 100_000), ("maa", "मा", 100_000)],
            learner: learner
        )
        await learner.injectBoost(input: "ma", output: "मा", freq: 1, when: Date(), matchesInput: false)
        let results = await engine.candidates(for: "ma")
        XCTAssertEqual(results.first?.output, "म")
    }

    func testStaleLearnedPickDropsOutOfExactTier() async {
        let learner = FakeLearner()
        let engine = makeEngine(
            dictPairs: [("nepal", "नेपाल", 100_000), ("nepalma", "नेपालमा", 6_740)],
            learner: learner
        )
        let aYearAgo = Date().addingTimeInterval(-365 * 86_400)
        await learner.injectBoost(input: "nep", output: "नेपालमा", freq: 1, when: aYearAgo)
        let results = await engine.candidates(for: "nep")
        XCTAssertEqual(results.first?.output, "नेपाल")
    }

    func testCapitalizedInputKeepsRuleReadingVisible() async {
        // Lowercase completions for `dar` would fill the window; the rule
        // layer's retroflex reading for `Dar` must still get a slot.
        let pairs: [(String, String, Int)] = (0..<20).map { ("dar\($0)", "दर\($0)", 1000 - $0) }
        let engine = makeEngine(dictPairs: pairs, fallback: RuleDictionarySource())
        let results = await engine.candidates(for: "Dar", limit: 9)
        XCTAssertEqual(results.count, 9)
        XCTAssertTrue(results.contains { $0.output == "डर" }, "\(results.map(\.output))")
    }

    func testRuleReadingGetsASlotWhenCompletionsFillWindow() async {
        let pairs: [(String, String, Int)] = (0..<20).map { ("dilip\($0)", "दिलिप\($0)", 1000 - $0) }
        let engine = makeEngine(dictPairs: pairs, fallback: RuleDictionarySource())
        let results = await engine.candidates(for: "dilip", limit: 9)
        XCTAssertEqual(results.count, 9)
        XCTAssertEqual(results.last?.output, "दिलिप")
    }

    private func makeEngine(
        dictPairs: [(String, String, Int)],
        learner: LearnerSource = NoopLearner(),
        ranker: Ranker = Ranker(),
        fallback: DictionarySource? = nil
    ) -> SuggestionEngine {
        var trie = Trie()
        for (input, output, freq) in dictPairs {
            trie.insert(
                key: input,
                value: Candidate(output: output, romanInput: input, baseFrequency: freq, source: .system)
            )
        }
        let dict = StaticDictionary(trie: trie)
        return SuggestionEngine(dictionary: dict, learner: learner, fallback: fallback, ranker: ranker)
    }
}

private struct StaticDictionary: DictionarySource {
    let trie: Trie
    func candidates(for prefix: String) -> [Candidate] {
        trie.lookup(prefix: prefix)
    }
}

private struct NoopLearner: LearnerSource {
    func boostScores(for input: String) async -> [String: BoostScore] { [:] }
    func record(input: String, output: String, source: Candidate.Source) async {}
}

private actor FakeLearner: LearnerSource {
    private var boosts: [String: [String: BoostScore]] = [:]
    private(set) var recordedCount = 0

    func injectBoost(input: String, output: String, freq: Int, when: Date, matchesInput: Bool = true) {
        var perInput = boosts[input] ?? [:]
        let prev = perInput[output]
        let newFreq = (prev?.userFrequency ?? 0) + freq
        perInput[output] = BoostScore(userFrequency: newFreq, lastUsed: when, matchesInput: matchesInput)
        boosts[input] = perInput
    }

    func boostScores(for input: String) async -> [String: BoostScore] {
        boosts[input] ?? [:]
    }

    func record(input: String, output: String, source: Candidate.Source) async {
        recordedCount += 1
    }
}
