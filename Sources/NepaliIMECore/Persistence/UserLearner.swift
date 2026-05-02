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
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO selections (input, output, frequency, last_used, source)
                    VALUES (?, ?, 1, ?, ?)
                    ON CONFLICT(input, output) DO UPDATE SET
                        frequency = frequency + 1,
                        last_used = excluded.last_used,
                        source = excluded.source
                    """,
                    arguments: [input, output, now, source.rawValue]
                )
            }
        } catch {
            Log.learner.error("record failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func boostScores(for input: String) async -> [String: BoostScore] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT output, frequency, last_used FROM selections WHERE input = ?",
                    arguments: [input]
                )
                var out: [String: BoostScore] = [:]
                for row in rows {
                    let output: String = row["output"]
                    let freq: Int = row["frequency"]
                    let lastUsed: Double = row["last_used"]
                    out[output] = BoostScore(userFrequency: freq, lastUsed: Date(timeIntervalSince1970: lastUsed))
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
        return m
    }
}
