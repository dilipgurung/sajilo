import XCTest
@testable import NepaliIMECore

final class DictionaryManagerTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("DictionaryManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = tmpDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testParsesSystemTSV() throws {
        let sys = try writeTSV("system.tsv", lines: [
            "namaste\tनमस्ते\t100",
            "nam\tनाम\t50",
            "ghar\tघर\t80",
        ])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: nil)
        let results = mgr.candidates(for: "nam")
        let outputs = Set(results.map(\.output))
        XCTAssertEqual(outputs, ["नमस्ते", "नाम"])
    }

    func testIgnoresMalformedLines() throws {
        let sys = try writeTSV("system.tsv", lines: [
            "namaste\tनमस्ते\t100",
            "broken-line-no-tabs",
            "\tनाम\t50",
            "nam\t\t50",
            "ghar\tघर\tnotanumber",
        ])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: nil)
        XCTAssertEqual(mgr.candidates(for: "namaste").count, 1)
        XCTAssertEqual(mgr.candidates(for: "ghar").first?.baseFrequency, 1)
    }

    func testNFCNormalizesOutput() throws {
        let decomposed = "\u{0928}\u{092E}\u{0938}\u{094D}\u{0924}\u{0947}".decomposedStringWithCanonicalMapping
        let sys = try writeTSV("system.tsv", lines: [
            "namaste\t\(decomposed)\t100",
        ])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: nil)
        let result = mgr.candidates(for: "namaste").first
        XCTAssertEqual(result?.output, "नमस्ते".precomposedStringWithCanonicalMapping)
    }

    func testMergesUserDict() throws {
        let sys = try writeTSV("system.tsv", lines: [
            "namaste\tनमस्ते\t100",
        ])
        let user = try writeTSV("user.tsv", lines: [
            "kk\tकाठमाडौँ",
        ])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: user)
        let results = mgr.candidates(for: "kk")
        XCTAssertEqual(results.first?.output, "काठमाडौँ")
        XCTAssertEqual(results.first?.source, .user)
    }

    func testUserEntryWithoutFrequencyOutranksAnySystemEntry() throws {
        let sys = try writeTSV("system.tsv", lines: ["nepal\tनेपल\t100000"])
        let user = try writeTSV("user.tsv", lines: ["nepal\tनेपाल"])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: user)
        let userCand = mgr.candidates(for: "nepal").first { $0.source == .user }
        XCTAssertEqual(userCand?.baseFrequency, DictionaryManager.userDefaultFrequency)
        XCTAssertGreaterThan(DictionaryManager.userDefaultFrequency, 100_000)
    }

    func testPrefixLookupCapsCompletionsButKeepsExactMatches() throws {
        var lines = ["k\tक\t1"]
        lines += (0..<100).map { "k\($0)\tक\($0)\t\($0)" }
        let sys = try writeTSV("system.tsv", lines: lines)
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: nil, completionLimit: 5)
        let outputs = mgr.candidates(for: "k").map(\.output)
        XCTAssertTrue(outputs.contains("क"), "exact match always included")
        XCTAssertEqual(outputs.count, 6)
        XCTAssertTrue(outputs.contains("क99"), "highest-frequency completion kept")
        XCTAssertFalse(outputs.contains("क0"))
    }

    func testReloadUserDictionaryPicksUpEdits() throws {
        let sys = try writeTSV("system.tsv", lines: ["namaste\tनमस्ते\t100"])
        let user = try writeTSV("user.tsv", lines: ["kk\tकाठमाडौँ"])
        let mgr = try DictionaryManager(systemDictURL: sys, userDictURL: user)
        XCTAssertEqual(mgr.candidates(for: "kk").count, 1)

        try "kk\tकाठमाडौँ\nnp\tनेपाल\n".write(to: user, atomically: true, encoding: .utf8)
        try mgr.reloadUserDictionary()
        XCTAssertEqual(mgr.candidates(for: "np").first?.output, "नेपाल")
    }

    private func writeTSV(_ name: String, lines: [String]) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
