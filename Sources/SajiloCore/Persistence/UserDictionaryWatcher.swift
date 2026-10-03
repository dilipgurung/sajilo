import Foundation

/// Watches the user dictionary and calls `onChange` (debounced) after edits.
/// All mutable state is confined to `queue`.
public final class UserDictionaryWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let debounce: DispatchTimeInterval
    private let queue = DispatchQueue(label: "Sajilo.UserDictionaryWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    public init(
        url: URL,
        debounce: DispatchTimeInterval = .milliseconds(200),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        queue.async {
            self.ensureFileExists()
            self.startOnQueue(retriesLeft: 0)
        }
    }

    public func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Re-opens are retried briefly: editors that delete-then-recreate
    /// leave a window where the file doesn't exist. We never create the
    /// file here — doing so could race the editor's write.
    private func startOnQueue(retriesLeft: Int) {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            if retriesLeft > 0 {
                queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    self.startOnQueue(retriesLeft: retriesLeft - 1)
                }
            } else {
                Log.dict.error("UserDictionaryWatcher: cannot open \(self.url.path, privacy: .public)")
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            // Editors that save atomically replace the file; the old
            // descriptor then points at the unlinked inode, so re-open.
            if !src.data.isDisjoint(with: [.delete, .rename]) {
                self.startOnQueue(retriesLeft: 20)
            }
            self.scheduleChange()
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func stopOnQueue() {
        source?.cancel()
        source = nil
        pendingChange?.cancel()
        pendingChange = nil
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }
    }

    deinit {
        source?.cancel()
        pendingChange?.cancel()
    }
}
