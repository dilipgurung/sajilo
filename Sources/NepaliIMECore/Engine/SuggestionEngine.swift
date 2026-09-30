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
        // Dictionary keys are lowercase; capitals only carry meaning for
        // the rule layer (retroflex), which gets the input as typed.
        let raw = dictionary.candidates(for: romanInput.lowercased())

        // Always consult the learner: even when the dictionary fills the
        // window, a previous pick must be able to reorder it.
        let boosts = await learner.boostScores(for: romanInput)

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

        let ranked = ranker.rankWithTiers(candidates: merged, boosts: boosts, now: Date(), input: romanInput)
        let existing = Set(ranked.map(\.candidate.output))
        let ruleExtras = (fallback?.candidates(for: romanInput) ?? [])
            .filter { !existing.contains($0.output) }

        // The rule reading is the only way to get a word the dictionary
        // doesn't know, so keep a slot for it (two when the input has
        // capitals, which ask for a retroflex reading) — displacing only
        // prefix completions, never exact matches.
        let hasCapitals = romanInput != romanInput.lowercased()
        let reserve = min(ruleExtras.count, hasCapitals ? 2 : 1)
        let exactCount = ranked.prefix { $0.exact }.count
        let keep = max(min(exactCount, limit), limit - reserve)

        var result = ranked.prefix(keep).map(\.candidate)
        for c in ruleExtras where result.count < limit {
            result.append(c)
        }
        return result
    }

    public func recordSelection(input: String, output: String, source: Candidate.Source) async {
        await learner.record(input: input, output: output, source: source)
    }
}
