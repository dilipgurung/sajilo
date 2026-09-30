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

    // MARK: - Capital handling for non-retroflex letters

    func testNonRetroflexCapsAreCaseInsensitive() {
        // Letters that have no retroflex pair (K, M, P, ...) silently
        // fall back to their lowercase reading — no new alternatives.
        XCTAssertEqual(first("Kalam"), first("kalam"))
        XCTAssertEqual(first("Mero"),  first("mero"))
        XCTAssertEqual(first("Pani"),  first("pani"))
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

    // MARK: - Capital-letter retroflex (ITRANS convention)

    func testRetroflexCapitalSingleConsonants() {
        // T/D/N/S → ट/ड/ण/ष as the default (first) reading.
        XCTAssertEqual(first("T"), "ट")
        XCTAssertEqual(first("D"), "ड")
        XCTAssertEqual(first("N"), "ण")
        XCTAssertEqual(first("S"), "ष")
    }

    func testRetroflexCapitalAspirated() {
        // Th/Dh → ठ/ढ as the default reading.
        XCTAssertEqual(first("Th"), "ठ")
        XCTAssertEqual(first("Dh"), "ढ")
    }

    func testRetroflexAtWordStart() {
        // Taa = retroflex T + long aa = टा.
        XCTAssertEqual(first("Taa"), "टा")
    }

    func testRetroflexInsideWord() {
        // miThaai = m + i-matra + retroflex-Th + aa-matra + i. Default
        // parse uses retroflex; dental is also a multi-candidate alt.
        let parses = all("miThaai")
        XCTAssertTrue(parses.contains("मिठाइ"),
                      "expected retroflex reading मिठाइ in \(parses)")
        XCTAssertTrue(parses.contains("मिथाइ"),
                      "expected dental alt मिथाइ in \(parses)")
    }

    func testRetroflexClusterTriggersHalant() {
        // Capital T followed by another consonant still gets the
        // general consonant-cluster halant rule.
        XCTAssertEqual(first("Tk"), "ट्क")
    }

    // MARK: - Halant via `\`

    func testHalantSuppressesSchwa() {
        // `bas\` = b + a-schwa + s + halant → बस्.
        XCTAssertEqual(first("bas\\"), "बस्")
    }

    func testHalantBetweenConsonantsClusters() {
        // `bas\m` = बस् + म (no auto-halant since user already
        // explicitly halanted s, and lastConsonant resets).
        XCTAssertEqual(first("bas\\m"), "बस्म")
    }

    // MARK: - Anusvara via `*` and chandrabindu via `**`

    func testAnusvaraAttachesToPrevious() {
        // `man*` = म + n-schwa + ं → मनं.
        XCTAssertEqual(first("man*"), "मनं")
    }

    func testChandrabindu() {
        // `**` is a 2-char token, longest-match wins over `*`.
        // `kahaa**` → क + ा + h + ा + ँ (chandrabindu after long-aa).
        let parses = all("kahaa**")
        XCTAssertTrue(parses.contains("कहाँ"),
                      "expected कहाँ in \(parses)")
    }

    // MARK: - Word-start `om → ॐ` (multi-candidate)

    func testOmAtWordStartProducesBothReadings() {
        let parses = all("om")
        XCTAssertTrue(parses.contains("ॐ"),  "expected ॐ in \(parses)")
        XCTAssertTrue(parses.contains("ओम"), "expected ओम in \(parses)")
    }

    func testOmMidWordIsJustOM() {
        // `kom` mid-word — not at pos 0, so word-start special doesn't
        // fire. We only get the natural k-o-m parse (कोम), plus any
        // anusvara branch on trailing m (कों).
        let parses = all("kom")
        XCTAssertTrue(parses.contains("कोम"), "expected कोम in \(parses)")
        XCTAssertFalse(parses.contains(where: { $0.contains("ॐ") }),
                       "ॐ should NOT appear mid-word in \(parses)")
    }

    // MARK: - `yna` and split alternative

    func testYnaProducesPalatalNasal() {
        let parses = all("yna")
        XCTAssertTrue(parses.contains("ञ"),  "expected ञ in \(parses)")
        XCTAssertTrue(parses.contains("य्न"), "expected split य्न in \(parses)")
    }

    // MARK: - `rri / rree` aliases for vocalic R

    func testRriIsVocalicR() {
        // `rri` independent vocalic R, plus a multi-candidate split alt.
        let parses = all("rri")
        XCTAssertTrue(parses.contains("ऋ"), "expected ऋ in \(parses)")
    }

    func testDoubledRAfterVowelIsRaCluster() {
        XCTAssertEqual(first("harri"), "हर्रि")
        XCTAssertFalse(all("rri").contains("रृ"), "\(all("rri"))")
        XCTAssertFalse(all("harri").contains("हरृ"), "\(all("harri"))")
    }

    func testRreeIsLongVocalicR() {
        let parses = all("rree")
        XCTAssertTrue(parses.contains("ॠ"), "expected ॠ in \(parses)")
    }

    func testRriMatraAfterConsonant() {
        // `krri` = क + ृ matra (with the multi-candidate split alt also
        // produced — at minimum, कृ should be in the parse list).
        let parses = all("krri")
        XCTAssertTrue(parses.contains("कृ"), "expected कृ in \(parses)")
    }

    func testCapitalRetroflexAlsoEmitsDentalAlternative() {
        // The user's earlier `Dilip = दिलिप` example: typing the name
        // with capital D produces both readings. User picks dental;
        // the learner remembers it for next time.
        let parses = all("Dilip")
        XCTAssertTrue(parses.contains("डिलिप"),
                      "expected retroflex reading डिलिप in \(parses)")
        XCTAssertTrue(parses.contains("दिलिप"),
                      "expected dental alt दिलिप in \(parses)")
    }


    // MARK: - Vocalic R placement and Latin leakage

    func testRiAfterVowelIsRaPlusIMatra() {
        XCTAssertEqual(first("hari"), "हरि")
        XCTAssertEqual(first("giri"), "गिरि")
        XCTAssertEqual(first("pari"), "परि")
    }

    func testRiAtWordStartAndAfterConsonantStaysVocalic() {
        XCTAssertEqual(first("rishi"), "ऋशि")
        XCTAssertEqual(first("kri"), "कृ")
    }

    func testRiAfterConsonantOffersSplitAlternative() {
        XCTAssertTrue(all("priya").contains("प्रिय"), "\(all("priya"))")
    }

    func testUnmappedLatinLettersDoNotLeak() {
        XCTAssertEqual(first("cat"), "कत")
        XCTAssertEqual(first("zoo"), "जू")
        XCTAssertEqual(first("xray"), "क्स्रय")
        for w in ["cat", "zoo", "xray", "quick", "Cxqz"] {
            for parse in all(w) {
                XCTAssertFalse(parse.contains(where: { $0.isASCII && $0.isLetter }), "\(w) → \(parse)")
            }
        }
    }
}
