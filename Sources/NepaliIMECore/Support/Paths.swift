import Foundation

public enum Paths {
    public static let appName = "NepaliIME"

    // Created once on first access rather than on every property read.
    public static let applicationSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Trie cache directory used by versions ≤ 0.1.0; removed at startup.
    public static var legacyCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    public static var userDictionary: URL {
        applicationSupportDirectory.appendingPathComponent("user_dict.tsv", isDirectory: false)
    }

    public static var userLearnerDatabase: URL {
        applicationSupportDirectory.appendingPathComponent("learner.sqlite", isDirectory: false)
    }

    public static var bundledSystemDict: URL? {
        Bundle.main.url(forResource: "system_dict", withExtension: "tsv")
    }
}
