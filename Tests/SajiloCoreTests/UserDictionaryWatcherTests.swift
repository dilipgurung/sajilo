import XCTest
@testable import SajiloCore

final class UserDictionaryWatcherTests: XCTestCase {
    func testFiresAfterWriteAndSurvivesAtomicReplace() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = expectation(description: "change after in-place write")
        let second = expectation(description: "change after atomic replace")
        let counter = Counter()
        let watcher = UserDictionaryWatcher(url: url, debounce: .milliseconds(50)) {
            switch counter.increment() {
            case 1: first.fulfill()
            case 2: second.fulfill()
            default: break
            }
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.2)

        let handle = try FileHandle(forWritingTo: url)
        handle.write(Data("a\tअ\n".utf8))
        try handle.close()
        wait(for: [first], timeout: 2)

        // Atomic save (write temp + rename over), as most editors do.
        try "b\tब\n".write(to: url, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 2)
        watcher.stop()
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
