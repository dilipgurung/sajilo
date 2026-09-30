import Foundation
import GRDB

public actor UserLearner: LearnerSource {
    private let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        var config = Configuration()
        config.label = "NepaliIME.UserLearner"
        self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    public init(inMemory: Bool) throws {
        precondition(inMemory)
        var config = Configuration()
        config.label = "NepaliIME.UserLearner.memory"
        self.dbQueue = try DatabaseQueue(configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    public func record(input: String, output: String, source: Candidate.Source) async {
        let now = Date().timeIntervalSince1970
        let normalized = Self.normalizeForLearner(input)
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO selections (input, normalized_input, output, frequency, last_used, source)
                    VALUES (?, ?, ?, 1, ?, ?)
                    ON CONFLICT(input, output) DO UPDATE SET
                        frequency = frequency + 1,
                        last_used = excluded.last_used,
                        source = excluded.source,
                        normalized_input = excluded.normalized_input
                    """,
                    arguments: [input, normalized, output, now, source.rawValue]
                )
            }
        } catch {
            Log.learner.error("record failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns boost scores for the given Roman input. The query is
    /// normalized (sigils stripped, lowercased) so a forgiving lookup
    /// like `gaidakot` matches a literal stored key like `gai*DaakoT`.
    /// The literal `input` column stays intact for inspection / future
    /// migration to the user dictionary.
    public func boostScores(for input: String) async -> [String: BoostScore] {
        let normalized = Self.normalizeForLearner(input)
        guard !normalized.isEmpty else { return [:] }
        let literal = input.lowercased()
        do {
            return try await dbQueue.read { db in
                // LIMIT 50 — the candidate window only ever shows ~9
                // results; pulling more than that for the merge step is
                // wasted work even at high learner-DB sizes.
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT input, output, frequency, last_used
                    FROM selections
                    WHERE normalized_input = ?
                    LIMIT 50
                    """,
                    arguments: [normalized]
                )
                var out: [String: BoostScore] = [:]
                for row in rows {
                    let output: String = row["output"]
                    let freq: Int = row["frequency"]
                    let lastUsed: Double = row["last_used"]
                    let matches = (row["input"] as String).lowercased() == literal
                    // Same output may appear from multiple literal keys
                    // that all normalize to the same value — sum the
                    // frequencies, keep the most-recent last_used.
                    if let prev = out[output] {
                        out[output] = BoostScore(
                            userFrequency: prev.userFrequency + freq,
                            lastUsed: max(prev.lastUsed, Date(timeIntervalSince1970: lastUsed)),
                            matchesInput: prev.matchesInput || matches
                        )
                    } else {
                        out[output] = BoostScore(
                            userFrequency: freq,
                            lastUsed: Date(timeIntervalSince1970: lastUsed),
                            matchesInput: matches
                        )
                    }
                }
                return out
            }
        } catch {
            Log.learner.error("boostScores failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    public func selectionCount() async -> Int {
        (try? await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM selections") ?? 0
        }) ?? 0
    }

    /// Normalizes a literal Roman input to a canonical lookup key.
    /// Three transformations:
    ///   1. Strip the combining-mark sigils `\` (halant) and `*`
    ///      (anusvara / chandrabindu).
    ///   2. Lowercase everything (so capital retroflex T/D/N/S/Th/Dh
    ///      collapse to their dental Roman keys).
    ///   3. Collapse two identical adjacent ASCII vowels into one
    ///      (so `aa→a`, `ee→e`, `ii→i`, `oo→o`, `uu→u`).
    /// Effect: `gai*DaakoT`, `gaiNDakoT`, and `gaidakot` all normalize
    /// to `gaidakot` — typing the simplest form retrieves entries
    /// stored from any of the more elaborate spellings.
    static func normalizeForLearner(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        var prev: Character = "\0"
        for ch in s {
            if ch == "\\" || ch == "*" { continue }
            for lc in String(ch).lowercased() {
                // Collapse repeated ASCII vowels.
                if lc == prev, "aeiou".contains(lc) { continue }
                out.append(lc)
                prev = lc
            }
        }
        return out
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE selections (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    input       TEXT    NOT NULL,
                    output      TEXT    NOT NULL,
                    frequency   INTEGER NOT NULL DEFAULT 1,
                    last_used   REAL    NOT NULL,
                    source      TEXT    NOT NULL,
                    UNIQUE(input, output)
                );
                CREATE INDEX idx_selections_input ON selections(input);
            """)
        }
        // Add normalized_input column + index, backfill for existing rows.
        m.registerMigration("v2_normalized_input") { db in
            try db.execute(sql: """
                ALTER TABLE selections ADD COLUMN normalized_input TEXT;
                CREATE INDEX idx_selections_normalized ON selections(normalized_input);
            """)
            let started = Date()
            var backfilled = 0
            let rows = try Row.fetchAll(db, sql: "SELECT id, input FROM selections WHERE normalized_input IS NULL")
            for row in rows {
                let id: Int64 = row["id"]
                let input: String = row["input"]
                let normalized = normalizeForLearner(input)
                try db.execute(
                    sql: "UPDATE selections SET normalized_input = ? WHERE id = ?",
                    arguments: [normalized, id]
                )
                backfilled += 1
            }
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            Log.learner.info("normalized_input backfill: \(backfilled) rows in \(elapsedMs)ms")
        }
        return m
    }
}
