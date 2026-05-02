import Foundation

/// Deterministic Roman → Devanagari transliteration grammar.
///
/// Produces a Devanagari rendering of any Roman input character-by-character,
/// using a longest-match left-to-right tokenizer over a static rule table.
/// Used by the IME for two purposes:
///
///   1. Live marked-text preview (controller renders the current buffer
///      transliterated as the user types).
///   2. Fallback `DictionarySource` (RuleDictionarySource) so novel words
///      not in the dictionary still produce a usable candidate.
///
/// The grammar is tuned for Nepali typing conventions:
///   - Inherent schwa is preserved at end of word (दिलिप, not दिलिप्).
///   - Consonant-consonant junctions get a halant inserted automatically
///     (`gar` → गर, `garcha` → गर्छ).
///   - Case is ignored (the input "Dilip" maps the same as "dilip").
///   - Dental t/d/n is the default; retroflex variants must come from the
///     dictionary layer.
///
/// Pure value type, `Sendable`, no I/O. Safe to call from any context.
public struct RuleTransliterator: Sendable {

    public enum Scheme: Sendable {
        case nepaliPhonetic
    }

    public init(scheme: Scheme = .nepaliPhonetic) {
        // Only one scheme today; the parameter exists so a future
        // ITRANS/Hunterian/IAST mode can be added without a breaking change.
        _ = scheme
    }

    public func transliterate(_ roman: String) -> String {
        guard !roman.isEmpty else { return "" }
        let chars = Array(roman.lowercased())
        var output = ""
        var i = 0
        var lastConsonant: String? = nil  // raw consonant token, for halant logic

        while i < chars.count {
            // Try longest match first: 3 → 2 → 1 chars.
            var matched: (kind: TokenKind, len: Int)? = nil
            for size in stride(from: 3, through: 1, by: -1) {
                guard i + size <= chars.count else { continue }
                let key = String(chars[i..<(i + size)])
                if let v = vowelTable[key] {
                    matched = (.vowel(v), size); break
                }
                if let c = consonantTable[key] {
                    matched = (.consonant(key, c), size); break
                }
            }

            guard let m = matched else {
                // Unknown character (digit, punctuation, latin letter not in table).
                // Flush any pending consonant unchanged (its inherent schwa stays)
                // then append the raw char.
                output.append(chars[i])
                lastConsonant = nil
                i += 1
                continue
            }

            switch m.kind {
            case .vowel(let v):
                if lastConsonant != nil {
                    // Vowel after consonant → matra absorbs the consonant's schwa.
                    output += v.matra
                } else {
                    output += v.independent
                }
                lastConsonant = nil

            case .consonant(let raw, let glyph):
                if lastConsonant != nil {
                    // Consonant directly after another consonant → halant on the
                    // previous one (already emitted; insert virama between them).
                    output += "्"
                }
                output += glyph
                lastConsonant = raw
            }

            i += m.len
        }

        return output
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

    /// Vowel tokens (longest first wins by virtue of the 3→2→1 match loop).
    /// Each maps to (independent form for word-start, matra for after consonant).
    /// "a" has empty matra because it's the inherent schwa already present.
    private var vowelTable: [String: VowelGlyph] {
        Self._vowelTable
    }
    private static let _vowelTable: [String: VowelGlyph] = [
        // 2-char digraphs FIRST so the matcher's longest-match loop picks them up.
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

    /// Consonant tokens. Glyph carries inherent schwa (e.g. क = "ka" by default);
    /// a following vowel-matra absorbs the schwa, and a following consonant
    /// triggers automatic halant insertion.
    private var consonantTable: [String: String] {
        Self._consonantTable
    }
    private static let _consonantTable: [String: String] = [
        // 3-char compound consonants (matched first by longest-match loop).
        "ksh": "क्ष",
        "shr": "श्र",
        "chh": "छ",

        // 2-char aspirates / common digraphs.
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
        "gy": "ज्ञ",   // common phonetic for ज्ञ in Nepali typing

        // Single-char consonants.
        "k": "क",
        "g": "ग",
        "j": "ज",
        "t": "त",
        "d": "द",
        "n": "न",
        "p": "प",
        "f": "फ",
        "b": "ब",
        "m": "म",
        "y": "य",
        "r": "र",
        "l": "ल",
        "v": "व",
        "w": "व",
        "s": "स",
        "h": "ह",
    ]
}
