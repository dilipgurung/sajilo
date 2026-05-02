import XCTest
@testable import NepaliIMECore

final class RankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let ranker = Ranker(alpha: 50, halfLifeDays: 21)

    func testNoBoostReturnsBaseFrequency() {
        let s = ranker.score(baseFrequency: 100, boost: nil, now: now)
        XCTAssertEqual(s, 100, accuracy: 0.001)
    }

    func testRecentBoostAddsAlphaTimesUserFreq() {
        let boost = BoostScore(userFrequency: 1, lastUsed: now)
        let s = ranker.score(baseFrequency: 0, boost: boost, now: now)
        XCTAssertEqual(s, 50, accuracy: 0.001)
    }

    func testHalfLifeDecay() {
        let boost = BoostScore(userFrequency: 1, lastUsed: now.addingTimeInterval(-21 * 86_400))
        let s = ranker.score(baseFrequency: 0, boost: boost, now: now)
        XCTAssertEqual(s, 25, accuracy: 0.5)
    }

    func testHighUserFrequencyBeatsHigherBaseFreq() {
        let baseOnly = ranker.score(baseFrequency: 200, boost: nil, now: now)
        let boost = BoostScore(userFrequency: 10, lastUsed: now)
        let withBoost = ranker.score(baseFrequency: 50, boost: boost, now: now)
        XCTAssertGreaterThan(withBoost, baseOnly)
    }

    func testAncientBoostNearlyZero() {
        let oneYearAgo = now.addingTimeInterval(-365 * 86_400)
        let boost = BoostScore(userFrequency: 5, lastUsed: oneYearAgo)
        let s = ranker.score(baseFrequency: 100, boost: boost, now: now)
        XCTAssertEqual(s, 100, accuracy: 0.5)
    }

    func testRankCandidatesSortsDescending() {
        let cands = [
            Candidate(output: "A", romanInput: "x", baseFrequency: 10, source: .system),
            Candidate(output: "B", romanInput: "x", baseFrequency: 100, source: .system),
            Candidate(output: "C", romanInput: "x", baseFrequency: 50, source: .system),
        ]
        let ranked = ranker.rank(candidates: cands, boosts: [:], now: now)
        XCTAssertEqual(ranked.map(\.output), ["B", "C", "A"])
    }

    func testRankPromotesUserChoice() {
        let cands = [
            Candidate(output: "A", romanInput: "x", baseFrequency: 200, source: .system),
            Candidate(output: "B", romanInput: "x", baseFrequency: 50, source: .system),
        ]
        let boosts = ["B": BoostScore(userFrequency: 10, lastUsed: now)]
        let ranked = ranker.rank(candidates: cands, boosts: boosts, now: now)
        XCTAssertEqual(ranked.first?.output, "B")
    }

    func testRankDedupesByOutputKeepingHighestScore() {
        let cands = [
            Candidate(output: "नाम", romanInput: "nam", baseFrequency: 100, source: .system),
            Candidate(output: "नाम", romanInput: "naam", baseFrequency: 50, source: .system),
        ]
        let ranked = ranker.rank(candidates: cands, boosts: [:], now: now)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.output, "नाम")
    }
}
