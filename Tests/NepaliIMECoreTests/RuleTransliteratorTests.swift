import XCTest
@testable import NepaliIMECore

final class RuleTransliteratorTests: XCTestCase {
    private let t = RuleTransliterator()

    /// First (default) parse — what the longest-match grammar produces.
    private func first(_ s: String) -> String? {
        t.first(s)
    }

    /// All parses — ordered, default first.
    private func all(_ s: String) -> [String] {
        t.transliterate(s)
    }

    // MARK: - Vowels (independent forms at word start)

    func testIndependentVowels() {
        XCTAssertEqual(first("a"), "अ")
        XCTAssertEqual(first("aa"), "आ")
        XCTAssertEqual(first("i"), "इ")
        XCTAssertEqual(first("ee"), "ई")
        XCTAssertEqual(first("u"), "उ")
        XCTAssertEqual(first("oo"), "ऊ")
        XCTAssertEqual(first("e"), "ए")
        XCTAssertEqual(first("ai"), "ऐ")
        XCTAssertEqual(first("o"), "ओ")
        XCTAssertEqual(first("au"), "औ")
    }

    // MARK: - Single consonant carries inherent schwa

    func testInherentSchwa() {
        XCTAssertEqual(first("k"), "क")
        XCTAssertEqual(first("m"), "म")
        XCTAssertEqual(first("r"), "र")
        XCTAssertEqual(first("h"), "ह")
    }

    // MARK: - Consonant + vowel matra

    func testConsonantPlusVowelMatra() {
        XCTAssertEqual(first("ka"), "क")     // 'a' is the inherent schwa
        XCTAssertEqual(first("ki"), "कि")
        XCTAssertEqual(first("ku"), "कु")
        XCTAssertEqual(first("ke"), "के")
        XCTAssertEqual(first("ko"), "को")
        XCTAssertEqual(first("kaa"), "का")
        XCTAssertEqual(first("kee"), "की")
        XCTAssertEqual(first("koo"), "कू")
    }

    // MARK: - Aspirated digraphs

    func testAspiratedDigraphs() {
        XCTAssertEqual(first("kha"), "ख")
        XCTAssertEqual(first("gha"), "घ")
        XCTAssertEqual(first("cha"), "च")
        XCTAssertEqual(first("chha"), "छ")
        XCTAssertEqual(first("jha"), "झ")
        XCTAssertEqual(first("tha"), "थ")
        XCTAssertEqual(first("dha"), "ध")
        XCTAssertEqual(first("pha"), "फ")
        XCTAssertEqual(first("bha"), "भ")
        XCTAssertEqual(first("sha"), "श")
    }

    // MARK: - Halant inserted between adjacent consonants

    func testConsonantClusterTriggersHalant() {
        XCTAssertEqual(first("gar"), "गर")
        XCTAssertEqual(first("garcha"), "गर्च")
        XCTAssertEqual(first("garchha"), "गर्छ")
    }

    // MARK: - Special compound consonants

    func testSpecialCompounds() {
        XCTAssertEqual(first("ksha"), "क्ष")
        XCTAssertEqual(first("kshama"), "क्षम")
        XCTAssertEqual(first("gyan"), "ज्ञन")
        XCTAssertEqual(first("shri"), "श्रि")
    }

    // MARK: - The user's earlier example: dilip → दिलिप

    func testDilipExample() {
        XCTAssertEqual(first("d"), "द")
        XCTAssertEqual(first("di"), "दि")
        XCTAssertEqual(first("dil"), "दिल")
        XCTAssertEqual(first("dili"), "दिलि")
        XCTAssertEqual(first("dilip"), "दिलिप")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitive() {
        XCTAssertEqual(first("Dilip"), "दिलिप")
        XCTAssertEqual(first("DILIP"), "दिलिप")
        XCTAssertEqual(first("KaThMaNdU"), first("kathmandu"))
    }

    // MARK: - Pass-through for unknown chars

    func testDigitsAndPunctuationPassThrough() {
        XCTAssertEqual(first("a1"), "अ1")
        XCTAssertEqual(first("dilip3"), "दिलिप3")
        XCTAssertEqual(first("a!"), "अ!")
    }

    // MARK: - Empty input

    func testEmpty() {
        XCTAssertEqual(all(""), [])
        XCTAssertNil(first(""))
    }

    // MARK: - "v" and "w" both map to व

    func testVAndWAreVa() {
        XCTAssertEqual(first("va"), "व")
        XCTAssertEqual(first("wa"), "व")
    }

    // MARK: - Branching rule A — single 'a' between consonant and vowel
    //          → produces a long-aa-matra alternative alongside the
    //          digraph / schwa default. The order isn't asserted —
    //          we just check both readings appear.

    func testGaiHasBothDiphthongAndCowReadings() {
        let parses = all("gai")
        XCTAssertTrue(parses.contains("गै"),  "expected diphthong reading गै in \(parses)")
        XCTAssertTrue(parses.contains("गाइ"), "expected cow reading गाइ in \(parses)")
    }

    func testGaeeProducesGaaee() {
        let parses = all("gaee")
        // Default longest-match: g + a-schwa + ee-independent → गई.
        // Long-aa alternative: g + aa-matra + ee-independent → गाई.
        XCTAssertTrue(parses.contains("गई"),  "expected schwa reading गई in \(parses)")
        XCTAssertTrue(parses.contains("गाई"), "expected long-aa reading गाई in \(parses)")
    }

    func testRamProducesLongAaAlternative() {
        // 'ram' = r + a + m. The branch fires whenever 'a' is between a
        // consonant and any further input (vowel or consonant), so we
        // get both रम (default) and राम (long-aa alt) — and रां
        // (long-aa + trailing-m anusvara).
        let parses = all("ram")
        XCTAssertTrue(parses.contains("रम"),  "expected default reading रम in \(parses)")
        XCTAssertTrue(parses.contains("राम"), "expected long-aa reading राम in \(parses)")
    }

    // MARK: - Branching rule B — trailing n/m at end of buffer after a
    //          vowel matra → anusvara alternative.

    func testGainProducesAnusvaraVariant() {
        let parses = all("gain")
        XCTAssertTrue(parses.contains("गैन"), "expected default reading गैन in \(parses)")
        XCTAssertTrue(parses.contains("गैं"), "expected anusvara reading गैं in \(parses)")
    }

    func testNaamProducesAnusvaraVariant() {
        // n + aa-matra + m at end. Default: नाम. Anusvara: नां.
        let parses = all("naam")
        XCTAssertTrue(parses.contains("नाम"), "expected default reading नाम in \(parses)")
        XCTAssertTrue(parses.contains("नां"), "expected anusvara reading नां in \(parses)")
    }

    func testManDefaultIsManNotAnusvara() {
        // The default (longest-match) reading of `man` is मन with no
        // anusvara — m + (schwa) + n with inherent schwa on n. Note:
        // the long-aa branch path can additionally emit मान and मां,
        // but the default ranks first and that's what users typing
        // "man" most often want.
        XCTAssertEqual(first("man"), "मन")
        // The default-path branch never produces anusvara — only the
        // long-aa alt path does. Verify the default itself is plain.
        let parses = all("man")
        XCTAssertEqual(parses.first, "मन")
    }

    func testGainuDoesNotTriggerAnusvara() {
        // 'gainu' has 'n' followed by 'u' — n is NOT at end of buffer,
        // so anusvara branch must not fire. The default consonant न
        // gets a 'u' matra → गैनु.
        let parses = all("gainu")
        XCTAssertTrue(parses.contains("गैनु"))
        XCTAssertFalse(parses.contains(where: { $0.contains("ं") }),
                       "no anusvara should appear when n is mid-word")
    }

    // MARK: - Cap on alternatives

    func testMaxAlternativesIsRespected() {
        let parses = t.transliterate("gain", maxAlternatives: 2)
        XCTAssertLessThanOrEqual(parses.count, 2)
    }
}
