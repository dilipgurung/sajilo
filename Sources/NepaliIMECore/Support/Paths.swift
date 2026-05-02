import Foundation

public enum Paths {
    public static let appName = "NepaliIME"

    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var cacheDirectory: URL {
        let dir = applicationSupportDirectory.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var systemDictCache: URL {
        cacheDirectory.appendingPathComponent("system_dict.bin", isDirectory: false)
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
