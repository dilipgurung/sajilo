import Foundation

public actor SuggestionEngine {
    private let dictionary: DictionarySource
    private let learner: LearnerSource
    private let ranker: Ranker

    public init(dictionary: DictionarySource, learner: LearnerSource, ranker: Ranker = Ranker()) {
        self.dictionary = dictionary
        self.learner = learner
        self.ranker = ranker
    }

    public func candidates(for romanInput: String, limit: Int = 9) async -> [Candidate] {
        guard !romanInput.isEmpty else { return [] }
        let raw = dictionary.candidates(for: romanInput)
        guard !raw.isEmpty else { return [] }
        let boosts = await learner.boostScores(for: romanInput)
        let ranked = ranker.rank(candidates: raw, boosts: boosts, now: Date())
        return Array(ranked.prefix(limit))
    }

    public func recordSelection(input: String, output: String, source: Candidate.Source) async {
        await learner.record(input: input, output: output, source: source)
    }
}
