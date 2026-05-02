import XCTest
@testable import NepaliIMECore

final class SuggestionEngineTests: XCTestCase {
    func testReturnsEmptyForEmptyInput() async {
        let engine = makeEngine(dictPairs: [("namaste", "नमस्ते", 100)])
        let results = await engine.candidates(for: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testReturnsRankedSystemCandidatesForPrefix() async {
        let engine = makeEngine(dictPairs: [
            ("nam", "नाम", 50),
            ("namaste", "नमस्ते", 100),
            ("namuna", "नमुना", 30),
            ("ghar", "घर", 80),
        ])
        let results = await engine.candidates(for: "nam")
        let outputs = results.map(\.output)
        XCTAssertFalse(outputs.contains("घर"))
        XCTAssertEqual(outputs.first, "नमस्ते")
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

    private func makeEngine(
        dictPairs: [(String, String, Int)],
        learner: LearnerSource = NoopLearner()
    ) -> SuggestionEngine {
        var trie = Trie()
        for (input, output, freq) in dictPairs {
            trie.insert(
                key: input,
                value: Candidate(output: output, romanInput: input, baseFrequency: freq, source: .system)
            )
        }
        let dict = StaticDictionary(trie: trie)
        return SuggestionEngine(dictionary: dict, learner: learner, ranker: Ranker())
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

    func injectBoost(input: String, output: String, freq: Int, when: Date) {
        var perInput = boosts[input] ?? [:]
        let prev = perInput[output]
        let newFreq = (prev?.userFrequency ?? 0) + freq
        perInput[output] = BoostScore(userFrequency: newFreq, lastUsed: when)
        boosts[input] = perInput
    }

    func boostScores(for input: String) async -> [String: BoostScore] {
        boosts[input] ?? [:]
    }

    func record(input: String, output: String, source: Candidate.Source) async {
        recordedCount += 1
    }
}
