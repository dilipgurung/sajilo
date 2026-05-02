import Foundation

/// Adapter that exposes the rule-based transliterator as a `DictionarySource`.
///
/// Returns one `Candidate` per alternative parse the transliterator
/// produces (up to `maxAlternatives`, default 4). All candidates have
/// `baseFrequency = 0` so SuggestionEngine ranks them below any dict
/// match; the engine also dedupes by output string before appending,
/// so a rule reading equal to a dict entry is suppressed.
public struct RuleDictionarySource: DictionarySource {
    private let transliterator: RuleTransliterator
    private let maxAlternatives: Int

    public init(
        transliterator: RuleTransliterator = RuleTransliterator(),
        maxAlternatives: Int = 4
    ) {
        self.transliterator = transliterator
        self.maxAlternatives = maxAlternatives
    }

    public func candidates(for prefix: String) -> [Candidate] {
        let parses = transliterator.transliterate(prefix, maxAlternatives: maxAlternatives)
        var seen = Set<String>()
        var out: [Candidate] = []
        for parse in parses {
            // Skip empty / pure-echo (digits-only inputs etc.) and dupes.
            guard !parse.isEmpty, parse != prefix, !seen.contains(parse) else { continue }
            seen.insert(parse)
            out.append(Candidate(
                output: parse,
                romanInput: prefix,
                baseFrequency: 0,
                source: .rule
            ))
        }
        return out
    }
}
