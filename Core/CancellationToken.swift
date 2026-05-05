import Foundation

final class CancellationToken: @unchecked Sendable {
    private let isCancelledLock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        isCancelledLock.lock()
        defer { isCancelledLock.unlock() }
        return _isCancelled
    }

    func cancel() {
        isCancelledLock.lock()
        _isCancelled = true
        isCancelledLock.unlock()
    }
}
