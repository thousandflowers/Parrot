import Foundation

/// Thread-safe one-way cancellation flag checked inside the llama.cpp token loop so a new
/// keystroke can abandon in-flight generation immediately.
final class CancelFlag: @unchecked Sendable {
    private var cancelled = false
    private let lock = NSLock()
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
