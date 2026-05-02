import Foundation

/// Deterministic Roman → Devanagari transliteration grammar that returns
/// multiple plausible parses for ambiguous inputs.
///
/// Used by the IME for one purpose: as a fallback `DictionarySource`
/// (`RuleDictionarySource`) so novel words not in the dictionary still
/// produce usable candidates. Returns up to 4 alternatives ranked with
/// the longest-match default first; the candidate window shows them all
/// and the learner remembers which one the user picked.
///
/// Tuned for Nepali typing conventions:
///   - Inherent schwa is preserved at end of word (दिलिप, not दिलिप्).
///   - Consonant-consonant junctions get a halant inserted automatically.
///   - Case is ignored.
///   - Default `t/d/n` is dental (use the dictionary for retroflex).
///
/// Branching points (where multiple parses are emitted):
///   - **Single `a` after a consonant before more input.** Default:
///     inherent schwa (matra empty). Alternative: long-aa matra (ा).
///     Lets `gai → गाइ`, `gaee → गाई`, `ram → राम` appear alongside
///     the schwa readings (गै, गई, रम).
///   - **Trailing `n`/`m` at end of buffer after a vowel matra.**
///     Default: emit consonant न/म with inherent schwa. Alternative:
///     emit anusvara (ं) on the previous syllable. Lets `gain → गैं`
///     and `nahin → नहीं` (well, the variant) appear alongside गैन/नहिन.
///
/// Pure value type, `Sendable`, no I/O.
public struct RuleTransliterator: Sendable {

    public enum Scheme: Sendable {
        case nepaliPhonetic
    }

    public init(scheme: Scheme = .nepaliPhonetic) {
        _ = scheme
    }

    /// Returns up to `maxAlternatives` plausible Devanagari parses,
    /// deduped, longest-match default first. Empty array for empty input.
    ///
    /// Case is significant for retroflex disambiguation: `T/D/N/S/Th/Dh`
    /// match the retroflex consonants (ट/ड/ण/ष/ठ/ढ) AND emit a dental
    /// alternative as a multi-candidate parse. Other capital letters
    /// (`K`, `M`, ...) silently fall back to their lowercase reading.
    public func transliterate(_ roman: String, maxAlternatives: Int = 4) -> [String] {
        let chars = Array(roman)
        guard !chars.isEmpty else { return [] }
        var raw: [String] = []
        // Hard internal cap on enumeration to prevent worst-case
        // combinatorial blowup on contrived inputs (e.g. "kakakaka").
        // Final unique cap is `maxAlternatives` after dedup.
        let internalCap = max(maxAlternatives * 8, 32)
        parse(
            chars: chars,
            pos: 0,
            output: "",
            lastConsonant: nil,
            prevWasExplicitVowel: false,
            results: &raw,
            cap: internalCap
        )
        var seen = Set<String>()
        var unique: [String] = []
        for r in raw where !seen.contains(r) {
            seen.insert(r)
            unique.append(r)
            if unique.count >= maxAlternatives { break }
        }
        return unique
    }

    /// Convenience: the single best parse, or `nil` for empty input.
    public func first(_ roman: String) -> String? {
        transliterate(roman, maxAlternatives: 1).first
    }

    // MARK: - Recursive parser

    private func parse(
        chars: [Character],
        pos: Int,
        output: String,
        lastConsonant: String?,
        prevWasExplicitVowel: Bool,
        results: inout [String],
        cap: Int
    ) {
        if results.count >= cap { return }
        if pos >= chars.count {
            results.append(output)
            return
        }

        // Longest-match: try 3-char, 2-char, 1-char tokens.
        // Vowels are case-insensitive (lookup uses lowercased key).
        // Consonants try the as-typed key first so `T` finds the
        // retroflex `T → ट`; if not found, fall back to lowercase so
        // `K` still resolves via the lowercase `k → क` token.
        var matched: (kind: TokenKind, len: Int)? = nil
        for size in stride(from: 3, through: 1, by: -1) {
            guard pos + size <= chars.count else { continue }
            let key = String(chars[pos..<(pos + size)])
            let lowerKey = key.lowercased()
            if let v = vowelTable[lowerKey] {
                matched = (.vowel(v), size); break
            }
            if let c = consonantTable[key] {
                matched = (.consonant(key, c), size); break
            }
            if key != lowerKey, let c = consonantTable[lowerKey] {
                // Capital letter w/o its own table entry — silently
                // degrade to the lowercase reading. (Only retroflex
                // T/D/N/S/Th/Dh have explicit uppercase entries.)
                matched = (.consonant(lowerKey, c), size); break
            }
        }

        guard let m = matched else {
            // Unknown char — pass through verbatim.
            parse(
                chars: chars,
                pos: pos + 1,
                output: output + String(chars[pos]),
                lastConsonant: nil,
                prevWasExplicitVowel: false,
                results: &results,
                cap: cap
            )
            return
        }

        switch m.kind {
        case .vowel(let v):
            // Default emission: matra after consonant, independent otherwise.
            if lastConsonant != nil {
                parse(
                    chars: chars,
                    pos: pos + m.len,
                    output: output + v.matra,
                    lastConsonant: nil,
                    prevWasExplicitVowel: !v.matra.isEmpty,
                    results: &results,
                    cap: cap
                )
            } else {
                parse(
                    chars: chars,
                    pos: pos + m.len,
                    output: output + v.independent,
                    lastConsonant: nil,
                    prevWasExplicitVowel: true,
                    results: &results,
                    cap: cap
                )
            }

            // Alternative: 'a' (single OR first char of 'ai'/'au') after a
            // consonant followed by more input → treat as long-aa matra.
            // Produces गाइ for `gai`, गाई for `gaee`, राम for `ram`.
            if lastConsonant != nil,
               chars[pos] == "a",
               pos + 1 < chars.count {
                parse(
                    chars: chars,
                    pos: pos + 1,
                    output: output + "ा",
                    lastConsonant: nil,
                    prevWasExplicitVowel: true,
                    results: &results,
                    cap: cap
                )
            }

        case .consonant(let raw, let glyph):
            // Default emission: insert halant before this consonant if the
            // previous emission was also a consonant (cluster).
            let prefix = (lastConsonant != nil) ? "्" : ""
            parse(
                chars: chars,
                pos: pos + m.len,
                output: output + prefix + glyph,
                lastConsonant: raw,
                prevWasExplicitVowel: false,
                results: &results,
                cap: cap
            )

            // Alternative: the matched token was uppercase (a retroflex
            // like `T → ट`, `Th → ठ`) and a distinct lowercase pair
            // exists in the table (`t → त`, `th → थ`). Emit the dental
            // reading too so capital letters in proper-noun typing
            // (`Dilip`) still surface the case-insensitive form
            // alongside the retroflex.
            let loweredRaw = raw.lowercased()
            if loweredRaw != raw,
               let dentalGlyph = consonantTable[loweredRaw],
               dentalGlyph != glyph {
                parse(
                    chars: chars,
                    pos: pos + m.len,
                    output: output + prefix + dentalGlyph,
                    lastConsonant: loweredRaw,
                    prevWasExplicitVowel: false,
                    results: &results,
                    cap: cap
                )
            }

            // Alternative: trailing 'n'/'m' at end of buffer after an
            // explicit vowel sound → anusvara (ं) on previous syllable
            // instead of the consonant. Produces गैं for `gain`,
            // नाँ-style for `naam` (alt of नाम), etc.
            if (raw == "n" || raw == "m"),
               pos + m.len >= chars.count,
               prevWasExplicitVowel {
                parse(
                    chars: chars,
                    pos: pos + m.len,
                    output: output + "ं",
                    lastConsonant: nil,
                    prevWasExplicitVowel: false,
                    results: &results,
                    cap: cap
                )
            }
        }
    }

    // MARK: - Token tables

    private enum TokenKind {
        case vowel(VowelGlyph)
        case consonant(String, String)  // (raw key, devanagari glyph)
    }

    private struct VowelGlyph {
        let independent: String
        let matra: String
    }

    private var vowelTable: [String: VowelGlyph] { Self._vowelTable }
    private static let _vowelTable: [String: VowelGlyph] = [
        // 2-char digraphs are matched first by the longest-match loop.
        "aa": VowelGlyph(independent: "आ", matra: "ा"),
        "ee": VowelGlyph(independent: "ई", matra: "ी"),
        "ii": VowelGlyph(independent: "ई", matra: "ी"),
        "oo": VowelGlyph(independent: "ऊ", matra: "ू"),
        "uu": VowelGlyph(independent: "ऊ", matra: "ू"),
        "ai": VowelGlyph(independent: "ऐ", matra: "ै"),
        "au": VowelGlyph(independent: "औ", matra: "ौ"),
        "ri": VowelGlyph(independent: "ऋ", matra: "ृ"),

        // Single-char vowels.
        "a": VowelGlyph(independent: "अ", matra: ""),
        "i": VowelGlyph(independent: "इ", matra: "ि"),
        "u": VowelGlyph(independent: "उ", matra: "ु"),
        "e": VowelGlyph(independent: "ए", matra: "े"),
        "o": VowelGlyph(independent: "ओ", matra: "ो"),
    ]

    private var consonantTable: [String: String] { Self._consonantTable }
    private static let _consonantTable: [String: String] = [
        // 3-char compound consonants.
        "ksh": "क्ष",
        "shr": "श्र",
        "chh": "छ",

        // 2-char retroflex aspirates (case-sensitive — capital letter
        // marks retroflex, ITRANS convention). Both readings reach the
        // candidate window via the dental-alternative branch.
        "Th": "ठ",
        "Dh": "ढ",

        // 2-char aspirates / common digraphs (lowercase = dental).
        "kh": "ख",
        "gh": "घ",
        "ng": "ङ",
        "ch": "च",
        "jh": "झ",
        "ny": "ञ",
        "th": "थ",
        "dh": "ध",
        "ph": "फ",
        "bh": "भ",
        "sh": "श",
        "gy": "ज्ञ",

        // Single-char retroflex consonants (capital letter convention).
        "T": "ट",
        "D": "ड",
        "N": "ण",
        "S": "ष",

        // Single-char consonants (lowercase = dental).
        "k": "क", "g": "ग", "j": "ज",
        "t": "त", "d": "द", "n": "न",
        "p": "प", "f": "फ", "b": "ब",
        "m": "म", "y": "य", "r": "र",
        "l": "ल", "v": "व", "w": "व",
        "s": "स", "h": "ह",
    ]
}
