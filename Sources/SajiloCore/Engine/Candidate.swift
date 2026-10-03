import Foundation

public struct Candidate: Sendable, Hashable, Codable {
    public let output: String
    public let romanInput: String
    public let baseFrequency: Int
    public let source: Source

    public enum Source: String, Sendable, Hashable, Codable {
        case system
        case user
        case learned
        case rule
    }

    public init(output: String, romanInput: String, baseFrequency: Int, source: Source) {
        self.output = output
        self.romanInput = romanInput
        self.baseFrequency = baseFrequency
        self.source = source
    }
}

public struct BoostScore: Sendable, Hashable {
    public let userFrequency: Int
    public let lastUsed: Date
    /// True when the pick was made for this literal input (ignoring case),
    /// false when it only matched via the learner's normalized key
    /// (e.g. a pick for `maa` seen while typing `ma`).
    public let matchesInput: Bool

    public init(userFrequency: Int, lastUsed: Date, matchesInput: Bool = true) {
        self.userFrequency = userFrequency
        self.lastUsed = lastUsed
        self.matchesInput = matchesInput
    }
}

public protocol DictionarySource: Sendable {
    func candidates(for prefix: String) -> [Candidate]
}

public protocol LearnerSource: Sendable {
    func boostScores(for input: String) async -> [String: BoostScore]
    func record(input: String, output: String, source: Candidate.Source) async
}
