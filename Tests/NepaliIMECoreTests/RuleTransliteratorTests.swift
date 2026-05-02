import XCTest
@testable import NepaliIMECore

final class RuleTransliteratorTests: XCTestCase {
    private let t = RuleTransliterator()

    // MARK: - Vowels (independent forms at word start)

    func testIndependentVowels() {
        XCTAssertEqual(t.transliterate("a"), "अ")
        XCTAssertEqual(t.transliterate("aa"), "आ")
        XCTAssertEqual(t.transliterate("i"), "इ")
        XCTAssertEqual(t.transliterate("ee"), "ई")
        XCTAssertEqual(t.transliterate("u"), "उ")
        XCTAssertEqual(t.transliterate("oo"), "ऊ")
        XCTAssertEqual(t.transliterate("e"), "ए")
        XCTAssertEqual(t.transliterate("ai"), "ऐ")
        XCTAssertEqual(t.transliterate("o"), "ओ")
        XCTAssertEqual(t.transliterate("au"), "औ")
    }

    // MARK: - Single consonant carries inherent schwa

    func testInherentSchwa() {
        XCTAssertEqual(t.transliterate("k"), "क")
        XCTAssertEqual(t.transliterate("m"), "म")
        XCTAssertEqual(t.transliterate("r"), "र")
        XCTAssertEqual(t.transliterate("h"), "ह")
    }

    // MARK: - Consonant + vowel → matra absorbs schwa

    func testConsonantPlusVowelMatra() {
        XCTAssertEqual(t.transliterate("ka"), "क")     // a is the inherent schwa
        XCTAssertEqual(t.transliterate("ki"), "कि")
        XCTAssertEqual(t.transliterate("ku"), "कु")
        XCTAssertEqual(t.transliterate("ke"), "के")
        XCTAssertEqual(t.transliterate("ko"), "को")
        XCTAssertEqual(t.transliterate("kaa"), "का")
        XCTAssertEqual(t.transliterate("kee"), "की")
        XCTAssertEqual(t.transliterate("koo"), "कू")
    }

    // MARK: - Aspirated digraphs

    func testAspiratedDigraphs() {
        XCTAssertEqual(t.transliterate("kha"), "ख")
        XCTAssertEqual(t.transliterate("gha"), "घ")
        XCTAssertEqual(t.transliterate("cha"), "च")
        XCTAssertEqual(t.transliterate("chha"), "छ")
        XCTAssertEqual(t.transliterate("jha"), "झ")
        XCTAssertEqual(t.transliterate("tha"), "थ")
        XCTAssertEqual(t.transliterate("dha"), "ध")
        XCTAssertEqual(t.transliterate("pha"), "फ")
        XCTAssertEqual(t.transliterate("bha"), "भ")
        XCTAssertEqual(t.transliterate("sha"), "श")
    }

    // MARK: - Halant inserted between adjacent consonants

    func testConsonantClusterTriggersHalant() {
        // "gar" — two consonants but separated by inherent schwa on r:
        // g + (a inherent on g) + r? Actually gar = g-a-r: 'g' consonant,
        // 'a' inherent → matra-empty (no glyph), 'r' consonant. So output
        // is गर with both keeping inherent schwa on g (absorbed by 'a')
        // and on r (word end, schwa preserved).
        XCTAssertEqual(t.transliterate("gar"), "गर")

        // "garcha" — 'g'+'a'(empty)+'r'+'ch'+'a'(empty). The r has no
        // explicit vowel after it but `ch` is a consonant token, so
        // a halant is inserted: ग + र + ् + च = गर्च
        XCTAssertEqual(t.transliterate("garcha"), "गर्च")

        // "garchha" — explicit chh: ग + र + ् + छ
        XCTAssertEqual(t.transliterate("garchha"), "गर्छ")
    }

    // MARK: - Special compound consonants

    func testSpecialCompounds() {
        XCTAssertEqual(t.transliterate("ksha"), "क्ष")
        XCTAssertEqual(t.transliterate("kshama"), "क्षम")
        XCTAssertEqual(t.transliterate("gyan"), "ज्ञन")  // gy=ज्ञ + a(inherent) + n(schwa)
        XCTAssertEqual(t.transliterate("shri"), "श्रि")  // shr digraph + i matra
    }

    // MARK: - The user's example

    func testDilipExample() {
        XCTAssertEqual(t.transliterate("d"), "द")
        XCTAssertEqual(t.transliterate("di"), "दि")
        XCTAssertEqual(t.transliterate("dil"), "दिल")
        XCTAssertEqual(t.transliterate("dili"), "दिलि")
        XCTAssertEqual(t.transliterate("dilip"), "दिलिप")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitive() {
        XCTAssertEqual(t.transliterate("Dilip"), "दिलिप")
        XCTAssertEqual(t.transliterate("DILIP"), "दिलिप")
        XCTAssertEqual(t.transliterate("KaThMaNdU"), t.transliterate("kathmandu"))
    }

    // MARK: - Pass-through for unknown chars

    func testDigitsAndPunctuationPassThrough() {
        XCTAssertEqual(t.transliterate("a1"), "अ1")
        XCTAssertEqual(t.transliterate("dilip3"), "दिलिप3")
        XCTAssertEqual(t.transliterate("a!"), "अ!")
    }

    // MARK: - Empty input

    func testEmpty() {
        XCTAssertEqual(t.transliterate(""), "")
    }

    // MARK: - Vowel-after-vowel (independent form, no matra)

    func testVowelAfterVowel() {
        // 'a' + 'i' is matched as 'ai' digraph (longest-match wins).
        XCTAssertEqual(t.transliterate("ai"), "ऐ")
        // But split with explicit consonant in between produces both.
        XCTAssertEqual(t.transliterate("ahi"), "अहि")
    }

    // MARK: - "v" and "w" both map to व

    func testVAndWAreVa() {
        XCTAssertEqual(t.transliterate("va"), "व")
        XCTAssertEqual(t.transliterate("wa"), "व")
    }
}
