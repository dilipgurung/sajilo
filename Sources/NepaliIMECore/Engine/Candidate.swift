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

    public init(userFrequency: Int, lastUsed: Date) {
        self.userFrequency = userFrequency
        self.lastUsed = lastUsed
    }
}

public protocol DictionarySource: Sendable {
    func candidates(for prefix: String) -> [Candidate]
}

public protocol LearnerSource: Sendable {
    func boostScores(for input: String) async -> [String: BoostScore]
    func record(input: String, output: String, source: Candidate.Source) async
}
