import Foundation

/// Adapter that exposes the rule-based transliterator as a `DictionarySource`,
/// so SuggestionEngine can pull a fallback candidate without any new protocol.
///
/// Returns at most one candidate per lookup. baseFrequency is 0 so the ranker
/// always sorts dictionary matches above this fallback. The engine is also
/// expected to dedupe by output string (suppress this candidate when the dict
/// already produced the same Devanagari).
public struct RuleDictionarySource: DictionarySource {
    private let transliterator: RuleTransliterator

    public init(transliterator: RuleTransliterator = RuleTransliterator()) {
        self.transliterator = transliterator
    }

    public func candidates(for prefix: String) -> [Candidate] {
        let deva = transliterator.transliterate(prefix)
        // Skip when transliteration is empty or didn't change anything (e.g.
        // pure-digit input). Without this guard the candidate list would
        // contain a useless echo of the user's Roman buffer.
        guard !deva.isEmpty, deva != prefix else { return [] }
        return [
            Candidate(
                output: deva,
                romanInput: prefix,
                baseFrequency: 0,
                source: .rule
            )
        ]
    }
}
