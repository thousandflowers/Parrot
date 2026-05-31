import Foundation

/// Runs a blocking AX read on a background thread and returns nil if it does not finish within
/// `milliseconds`. Keeps a hung/slow app from freezing the completion path on the main actor.
///
/// The timed-out work is abandoned, not killed (AX has no cancellation); it completes eventually
/// and its result is discarded. Never block on it.
func withAXTimeout<T: Sendable>(milliseconds: Int, _ work: @escaping @Sendable () -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
            }
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return Optional<T>.none
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
