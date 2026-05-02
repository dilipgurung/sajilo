import Foundation

@MainActor
public final class IMEServices {
    public static let shared = IMEServices()

    public private(set) var engine: SuggestionEngine?
    public private(set) var dictionaryManager: DictionaryManager?
    public private(set) var learner: UserLearner?
    public private(set) var watcher: UserDictionaryWatcher?

    private init() {}

    public func bootstrap() {
        guard engine == nil else { return }
        do {
            guard let systemDict = Paths.bundledSystemDict else {
                Log.lifecycle.error("Bundled system_dict.tsv not found in main bundle")
                return
            }
            let userDict = Paths.userDictionary
            let dictMgr = try DictionaryManager(
                systemDictURL: systemDict,
                userDictURL: userDict,
                cacheURL: Paths.systemDictCache
            )
            let learner = try UserLearner(databaseURL: Paths.userLearnerDatabase)
            let engine = SuggestionEngine(
                dictionary: dictMgr,
                learner: learner,
                fallback: RuleDictionarySource()
            )
            let watcher = UserDictionaryWatcher(url: userDict) { [weak dictMgr] in
                do { try dictMgr?.reloadUserDictionary() } catch {
                    Log.dict.error("reloadUserDictionary failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            watcher.start()

            self.dictionaryManager = dictMgr
            self.learner = learner
            self.engine = engine
            self.watcher = watcher
            Log.lifecycle.info("IMEServices bootstrap complete")
        } catch {
            Log.lifecycle.error("IMEServices bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
