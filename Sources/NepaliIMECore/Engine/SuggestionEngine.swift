import Foundation

public actor SuggestionEngine {
    private let dictionary: DictionarySource
    private let learner: LearnerSource
    private let fallback: DictionarySource?
    private let ranker: Ranker

    public init(
        dictionary: DictionarySource,
        learner: LearnerSource,
        fallback: DictionarySource? = nil,
        ranker: Ranker = Ranker()
    ) {
        self.dictionary = dictionary
        self.learner = learner
        self.fallback = fallback
        self.ranker = ranker
    }

    public func candidates(for romanInput: String, limit: Int = 9) async -> [Candidate] {
        guard !romanInput.isEmpty else { return [] }
        let raw = dictionary.candidates(for: romanInput)

        // Skip the learner DB hit when the dict has already filled the
        // candidate window — the learner can only contribute by ranking
        // or by introducing new outputs, and there's no room for either.
        let needsLearner = raw.count < limit
        let boosts: [String: BoostScore] = needsLearner
            ? await learner.boostScores(for: romanInput)
            : [:]

        // Promote learned outputs that aren't already in the dict to
        // first-class candidates so an entry like
        // `gaidakot → गैंडाकोट` (committed earlier) surfaces even when
        // no dictionary or rule candidate matches.
        var merged = raw
        if !boosts.isEmpty {
            let existing = Set(raw.map(\.output))
            for (output, _) in boosts where !existing.contains(output) {
                merged.append(Candidate(
                    output: output,
                    romanInput: romanInput,
                    baseFrequency: 0,
                    source: .learned
                ))
            }
        }

        var result: [Candidate] = []
        if !merged.isEmpty {
            let ranked = ranker.rank(candidates: merged, boosts: boosts, now: Date())
            result = Array(ranked.prefix(limit))
        }

        // Append the rule-based fallback last (and only if it adds something
        // new — dedupe by output to avoid showing both a dict and a rule
        // candidate with the same Devanagari).
        if let fallback, result.count < limit {
            let extras = fallback.candidates(for: romanInput)
            let existing = Set(result.map(\.output))
            for c in extras where !existing.contains(c.output) {
                result.append(c)
                if result.count >= limit { break }
            }
        }

        return result
    }

    public func recordSelection(input: String, output: String, source: Candidate.Source) async {
        await learner.record(input: input, output: output, source: source)
    }
}
