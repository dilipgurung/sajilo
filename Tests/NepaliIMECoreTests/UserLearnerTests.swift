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
}
