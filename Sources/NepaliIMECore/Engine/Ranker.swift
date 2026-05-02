import Foundation

public struct Ranker: Sendable {
    public let alpha: Double
    public let halfLifeDays: Double
    private let lambda: Double

    public init(alpha: Double = 50, halfLifeDays: Double = 21) {
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

    public func rank(candidates: [Candidate], boosts: [String: BoostScore], now: Date) -> [Candidate] {
        var bestByOutput: [String: (Candidate, Double)] = [:]
        for c in candidates {
            let s = score(baseFrequency: c.baseFrequency, boost: boosts[c.output], now: now)
            if let existing = bestByOutput[c.output] {
                if s > existing.1 { bestByOutput[c.output] = (c, s) }
            } else {
                bestByOutput[c.output] = (c, s)
            }
        }
        return bestByOutput.values
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.output < rhs.0.output
            }
            .map(\.0)
    }
}
