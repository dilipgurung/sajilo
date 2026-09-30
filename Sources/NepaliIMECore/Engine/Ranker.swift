import Foundation

/// Orders candidates in two tiers:
///   1. "Exact" candidates — the dictionary key equals the typed input
///      (case-insensitive), or the user picked this output for this
///      literal input recently enough (decayed uses ≥ `exactBoostThreshold`).
///   2. Everything else: prefix completions, stale picks, and picks that
///      only matched through the learner's normalized key.
/// Within a tier, by `baseFrequency + alpha · uses · exp(-λ · ageDays)`.
///
/// The default `alpha` is on the scale of the top system frequencies
/// (seed lemmas ship at 100,000), so a single recent pick lifts a word
/// above anything the user hasn't picked.
public struct Ranker: Sendable {
    public let alpha: Double
    public let halfLifeDays: Double
    public let exactBoostThreshold: Double
    private let lambda: Double

    /// With the default threshold of 0.5, one pick keeps a word in the
    /// exact tier for one half-life (21 days), two picks for two, etc.
    public init(alpha: Double = 100_000, halfLifeDays: Double = 21, exactBoostThreshold: Double = 0.5) {
        self.alpha = alpha
        self.halfLifeDays = halfLifeDays
        self.exactBoostThreshold = exactBoostThreshold
        self.lambda = log(2.0) / halfLifeDays
    }

    public func score(baseFrequency: Int, boost: BoostScore?, now: Date) -> Double {
        Double(baseFrequency) + alpha * decayedUses(boost, now: now)
    }

    private func decayedUses(_ boost: BoostScore?, now: Date) -> Double {
        guard let boost else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(boost.lastUsed) / 86_400)
        return Double(boost.userFrequency) * exp(-lambda * ageDays)
    }

    /// - Parameter input: the typed Roman input. When given, exact matches
    ///   and recent learned picks rank above everything else; when `nil`,
    ///   candidates are ordered by score alone.
    public func rank(
        candidates: [Candidate],
        boosts: [String: BoostScore],
        now: Date,
        input: String? = nil
    ) -> [Candidate] {
        rankWithTiers(candidates: candidates, boosts: boosts, now: now, input: input).map(\.candidate)
    }

    public func rankWithTiers(
        candidates: [Candidate],
        boosts: [String: BoostScore],
        now: Date,
        input: String?
    ) -> [(candidate: Candidate, exact: Bool)] {
        let key = input?.lowercased()
        var bestByOutput: [String: (candidate: Candidate, score: Double, exact: Bool)] = [:]
        for c in candidates {
            let boost = boosts[c.output]
            let s = score(baseFrequency: c.baseFrequency, boost: boost, now: now)
            var exact = false
            if key != nil {
                // Learned-only candidates carry the typed input as their
                // key, so only their boost can make them exact.
                let keyMatches = c.source != .learned && c.romanInput.lowercased() == key
                let recentPick = boost?.matchesInput == true
                    && decayedUses(boost, now: now) >= exactBoostThreshold
                exact = keyMatches || recentPick
            }
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
            .map { ($0.candidate, $0.exact) }
    }
}
