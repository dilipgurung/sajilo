import XCTest
@testable import NepaliIMECore

final class UserLearnerTests: XCTestCase {
    func testRecordAndQueryBoost() async throws {
        let learner = try UserLearner(inMemory: true)
        await learner.record(input: "nam", output: "नाम", source: .system)
        let boosts = await learner.boostScores(for: "nam")
        XCTAssertEqual(boosts["नाम"]?.userFrequency, 1)
    }

    func testRepeatedRecordIncrementsFrequency() async throws {
        let learner = try UserLearner(inMemory: true)
        for _ in 0..<5 {
            await learner.record(input: "nam", output: "नाम", source: .system)
        }
        let boosts = await learner.boostScores(for: "nam")
        XCTAssertEqual(boosts["नाम"]?.userFrequency, 5)
    }

    func testIndependentInputs() async throws {
        let learner = try UserLearner(inMemory: true)
        await learner.record(input: "nam", output: "नाम", source: .system)
        await learner.record(input: "ghar", output: "घर", source: .system)
        let nam = await learner.boostScores(for: "nam")
        let ghar = await learner.boostScores(for: "ghar")
        XCTAssertEqual(nam.count, 1)
        XCTAssertEqual(ghar.count, 1)
        XCTAssertNil(nam["घर"])
    }

    func testUpdatesLastUsedTimestamp() async throws {
        let learner = try UserLearner(inMemory: true)
        await learner.record(input: "nam", output: "नाम", source: .system)
        let first = await learner.boostScores(for: "nam")["नाम"]!.lastUsed
        try await Task.sleep(nanoseconds: 50_000_000)
        await learner.record(input: "nam", output: "नाम", source: .system)
        let second = await learner.boostScores(for: "nam")["नाम"]!.lastUsed
        XCTAssertGreaterThan(second, first)
    }

    // MARK: - Normalized lookup (literal key stored, forgiving query)

    func testNormalizedLookupMatchesLiteralKey() async throws {
        // Store with the exact literal Roman the user typed (markers + caps).
        let learner = try UserLearner(inMemory: true)
        await learner.record(input: "gai*DaakoT", output: "गैंडाकोट", source: .rule)

        // Forgiving query (no markers, lowercase) finds it.
        let easyQuery = await learner.boostScores(for: "gaidakot")
        XCTAssertEqual(easyQuery["गैंडाकोट"]?.userFrequency, 1)

        // Exact-literal query also finds it (normalization is idempotent
        // for already-clean input — well, the literal also normalizes to
        // gaidakot, so same row).
        let literalQuery = await learner.boostScores(for: "gai*DaakoT")
        XCTAssertEqual(literalQuery["गैंडाकोट"]?.userFrequency, 1)
    }

    func testMultipleLiteralsForSameNormalizedKeyAreSummed() async throws {
        let learner = try UserLearner(inMemory: true)
        // Two literal Roman inputs that both normalize to "gaidakot"
        // (one had the original sigils + caps, one is the simpler form
        // typed later), producing the SAME Devanagari output. The
        // boostScores loop sums frequencies across all matching rows.
        await learner.record(input: "gai*DaakoT", output: "गैंडाकोट", source: .rule)
        await learner.record(input: "Gaidakot",  output: "गैंडाकोट", source: .learned)
        let boosts = await learner.boostScores(for: "gaidakot")
        XCTAssertEqual(boosts["गैंडाकोट"]?.userFrequency, 2)
    }

    func testNormalizationRules() {
        // Strip sigils, lowercase capitals, collapse repeated vowels.
        XCTAssertEqual(UserLearner.normalizeForLearner("gai*DaakoT"), "gaidakot")
        XCTAssertEqual(UserLearner.normalizeForLearner("bas\\"),      "bas")
        XCTAssertEqual(UserLearner.normalizeForLearner("kahaa**"),    "kaha")
        XCTAssertEqual(UserLearner.normalizeForLearner("Dilip"),      "dilip")
        XCTAssertEqual(UserLearner.normalizeForLearner("namaste"),    "namaste")
        XCTAssertEqual(UserLearner.normalizeForLearner("DaakTar"),    "daktar")
        // Vowel collapse only fires on identical adjacent vowels —
        // distinct adjacent vowels (ai, au) stay as-is.
        XCTAssertEqual(UserLearner.normalizeForLearner("aim"),        "aim")
        XCTAssertEqual(UserLearner.normalizeForLearner("auto"),       "auto")
    }
}
