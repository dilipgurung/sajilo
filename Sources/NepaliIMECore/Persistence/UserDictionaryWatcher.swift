import Foundation

public final class UserDictionaryWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "NepaliIME.UserDictionaryWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    public func start() {
        ensureFileExists()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.dict.error("UserDictionaryWatcher: cannot open \(self.url.path, privacy: .public)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        let restart: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.stop()
            self.start()
        }
        src.setEventHandler { [onChange] in
            let mask = src.data
            if mask.contains(.delete) || mask.contains(.rename) {
                restart()
            }
            onChange()
        }
        src.setCancelHandler { [fd] in
            close(fd)
        }
        self.fileDescriptor = fd
        self.source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }
    }

    deinit {
        stop()
    }
}
