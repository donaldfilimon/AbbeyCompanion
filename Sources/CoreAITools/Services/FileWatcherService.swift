import Foundation
import Observation

@MainActor
@Observable
package final class FileWatcherService {
    private(set) var lastChangeTime: Date?
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var watchedPath: String?

    package init() {}

    func startWatching(path: String, onChange: @escaping @Sendable @MainActor () -> Void) {
        stopWatching()
        watchedPath = path

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .global()
        )

        // Use a weak wrapper to avoid use-after-free if the source fires after deallocation
        let callback = onChange
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastChangeTime = Date()
                self.debounceTask?.cancel()
                self.debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled {
                        callback()
                    }
                }
            }
        }
        source.resume()
        self.source = source
    }

    func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        watchedPath = nil
    }

    /// Release the file descriptor and dispatch source even if the owner
    /// forgets to call `stopWatching()` (e.g. on app exit / store
    /// deallocation), preventing a leaked fd and source. The instance is
    /// main-actor owned, so teardown happens on the main actor.
    deinit {
        MainActor.assumeIsolated {
            stopWatching()
        }
    }
}
