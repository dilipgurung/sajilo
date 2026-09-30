import Foundation

/// Orders candidates in two tiers:
///   1. "Exact" candidates — the dictionary key equals the typed input
///      (case-insensitive) or the user has previously picked this output
///      for this input (it has a learner boost).
///   2. Prefix completions.
/// Within a tier, by `baseFrequency + alpha · uses · exp(-λ · ageDays)`.
///
/// The default `alpha` is on the scale of the top system frequencies
/// (seed lemmas ship at 100,000), so a single recent pick lifts a word
/// above anything the user hasn't picked.
public struct Ranker: Sendable {
    public let alpha: Double
    public let halfLifeDays: Double
    private let lambda: Double

    public init(alpha: Double = 100_000, halfLifeDays: Double = 21) {
        self.alpha = alpha
        self.halfLifeDays = halfLifeDays
        self.lambda = log(2.0) / halfLifeDays
    }

    public func score(baseFrequency: Int, boost: BoostScore?, now: Date) -> Double {
        let base = Double(baseFrequency)
        guard let boost else { return base }
        let ageDays = max(0, now.timeIntervalSince(boost.lastUsed) / 86_400)
        let decay = exp(-lambda * ageDays)
        return base + alpha * Double(boost.userFrequency) * decay
    }

    /// - Parameter input: the typed Roman input. When given, exact matches
    ///   and learned outputs rank above prefix completions; when `nil`,
    ///   candidates are ordered by score alone.
    public func rank(
        candidates: [Candidate],
        boosts: [String: BoostScore],
        now: Date,
        input: String? = nil
    ) -> [Candidate] {
        let key = input?.lowercased()
        var bestByOutput: [String: (candidate: Candidate, score: Double, exact: Bool)] = [:]
        for c in candidates {
            let boost = boosts[c.output]
            let s = score(baseFrequency: c.baseFrequency, boost: boost, now: now)
            let exact = key != nil && (boost != nil || c.romanInput.lowercased() == key)
            if let existing = bestByOutput[c.output] {
                let best = s > existing.score ? (c, s) : (existing.candidate, existing.score)
                bestByOutput[c.output] = (best.0, best.1, exact || existing.exact)
            } else {
                bestByOutput[c.output] = (c, s, exact)
            }
        }
        return bestByOutput.values
            .sorted { lhs, rhs in
                if lhs.exact != rhs.exact { return lhs.exact }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.candidate.output < rhs.candidate.output
            }
            .map(\.candidate)
    }
}
