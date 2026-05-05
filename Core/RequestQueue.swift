import Foundation

actor RequestQueue {
    static let shared = RequestQueue()

    private var queue: [LLMRequest] = []
    private var isProcessing = false

    struct LLMRequest {
        let id = UUID()
        let text: String
        let promptType: PromptType
        let priority: Priority
        let continuation: CheckedContinuation<CorrectionResult, Error>
        let deadline: Date

        enum Priority: Int, Comparable {
            case manual = 2
            case floatingEditor = 1
            case autoCheck = 0

            static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
        }
    }

    func enqueue(text: String, type: PromptType, priority: LLMRequest.Priority) async throws -> CorrectionResult {
        try await withTimeout(seconds: 60) { continuation in
            let request = LLMRequest(
                text: text,
                promptType: type,
                priority: priority,
                continuation: continuation,
                deadline: Date().addingTimeInterval(60)
            )
            queue.append(request)
            queue.sort { $0.priority > $1.priority }
            Task { await processQueue() }
        }
    }

    private func processQueue() async {
        guard !isProcessing, let request = queue.first else { return }

        if Date() > request.deadline {
            queue.removeFirst()
            request.continuation.resume(throwing: CorrectionError.serverTimeout)
            Task { await processQueue() }
            return
        }

        isProcessing = true
        queue.removeFirst()

        do {
            let service = LLMServiceFactory.make()
            let result = try await service.correct(text: request.text, promptType: request.promptType)
            request.continuation.resume(returning: result)
        } catch {
            request.continuation.resume(throwing: error)
        }

        // defer would be cleaner, but actors prevent it. Always reset after.
        isProcessing = false
        Task { await processQueue() }
    }
}

func withTimeout<T>(
    seconds: TimeInterval,
    body: @escaping (CheckedContinuation<T, Error>) -> Void
) async throws -> T {
    final class ContinuationBox<T>: @unchecked Sendable {
        var continuation: CheckedContinuation<T, Error>?
        let lock = NSLock()
        func resume(throwing error: Error) {
            lock.lock(); defer { lock.unlock() }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
    let box = ContinuationBox<T>()

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    box.lock.lock(); box.continuation = continuation; box.lock.unlock()
                    body(continuation)
                }
            } onCancel: {
                box.resume(throwing: CancellationError())
            }
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CorrectionError.serverTimeout
        }
        guard let result = try await group.next() else { throw CorrectionError.serverTimeout }
        group.cancelAll()
        return result
    }
}
