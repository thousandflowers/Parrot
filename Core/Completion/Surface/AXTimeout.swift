import Foundation
import os

/// Runs a blocking AX read on a background thread and returns nil if it does not finish within
/// `milliseconds`. Keeps a hung/slow app from freezing the completion path on the main actor.
///
/// The timed-out work is abandoned, not killed (AX has no cancellation); it completes eventually
/// and its result is discarded. Never block on it. The caller resumes as soon as EITHER the work
/// or the deadline finishes — a task group would instead wait for the non-cancellable work.
func withAXTimeout<T: Sendable>(milliseconds: Int, _ work: @escaping @Sendable () -> T) async -> T? {
    await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
        let once = ResumeOnce(cont)
        DispatchQueue.global(qos: .userInitiated).async { once.resume(work()) }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            once.resume(nil)
        }
    }
}

/// Resumes a continuation exactly once; later calls are ignored.
private final class ResumeOnce<T: Sendable>: Sendable {
    private let slot: OSAllocatedUnfairLock<CheckedContinuation<T?, Never>?>

    init(_ continuation: CheckedContinuation<T?, Never>) {
        slot = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(_ value: T?) {
        let cont = slot.withLock { state -> CheckedContinuation<T?, Never>? in
            defer { state = nil }
            return state
        }
        cont?.resume(returning: value)
    }
}
