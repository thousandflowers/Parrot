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
        let box: ContinuationBox<CorrectionResult>
        let deadline: Date
        let overrideServiceType: ServiceType?
        let overrideCustomPrompt: CustomPrompt?

        enum Priority: Int, Comparable {
            case manual = 2
            case floatingEditor = 1
            case autoCheck = 0

            static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
        }
    }

    func enqueue(
        text: String,
        type: PromptType,
        priority: LLMRequest.Priority,
        overrideServiceType: ServiceType? = nil,
        overrideCustomPrompt: CustomPrompt? = nil
    ) async throws -> CorrectionResult {
        guard text.count <= Constants.maxTextLength else {
            throw CorrectionError.textTooLong(length: text.count, maxLength: Constants.maxTextLength)
        }
        let box = ContinuationBox<CorrectionResult>()
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(60))
                box.resume(throwing: CorrectionError.serverTimeout)
            } catch {
                // Timeout task cancelled, body already completed
            }
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.lock.lock(); box.continuation = continuation; box.lock.unlock()
                guard !box.isResumed else { return }
                let request = LLMRequest(
                    text: text,
                    promptType: type,
                    priority: priority,
                    box: box,
                    deadline: Date().addingTimeInterval(60),
                    overrideServiceType: overrideServiceType,
                    overrideCustomPrompt: overrideCustomPrompt
                )
                if let insertAt = self.queue.firstIndex(where: { $0.priority < priority }) {
                    self.queue.insert(request, at: insertAt)
                } else {
                    self.queue.append(request)
                }
                Task { await self.processQueue() }
            }
        } onCancel: {
            box.resume(throwing: CancellationError())
        }
    }

    private func processQueue() async {
        guard !isProcessing, let request = queue.first else { return }
        isProcessing = true

        if Date() > request.deadline {
            queue.removeFirst()
            isProcessing = false
            request.box.resume(throwing: CorrectionError.serverTimeout)
            Task { await processQueue() }
            return
        }

        queue.removeFirst()

        do {
            let service: LLMService
            let serviceType: ServiceType
            if let overrideType = request.overrideServiceType {
                service = LLMServiceFactory.make(with: overrideType)
                serviceType = overrideType
            } else {
                service = LLMServiceFactory.make()
                serviceType = LLMServiceFactory.resolveDefaultServiceType()
            }
            let modelID = resolveModelID(for: serviceType)

            if let cached = await ResultCache.shared.get(for: request.text, modelID: modelID) {
                isProcessing = false
                request.box.resume(returning: cached)
                Task { await processQueue() }
                return
            }

            let promptType: PromptType
            if let customPrompt = request.overrideCustomPrompt {
                promptType = .custom(name: customPrompt.name, template: customPrompt.template)
            } else {
                promptType = request.promptType
            }

            let result = try await service.correct(text: request.text, promptType: promptType)
            await ResultCache.shared.set(result, for: request.text, modelID: modelID)
            isProcessing = false
            request.box.resume(returning: result)
        } catch {
            isProcessing = false
            guard Date() <= request.deadline else {
                request.box.resume(throwing: CorrectionError.serverTimeout)
                Task { await processQueue() }
                return
            }
            request.box.resume(throwing: error)
        }

        Task { await processQueue() }
    }

    private nonisolated func resolveModelID(for serviceType: ServiceType) -> String {
        switch serviceType {
        case .stub:
            return "stub-v1"
        case .local:
            let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
            return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local-qwen"
        case .remote:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
        case .ollama:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2"
        case .openRouter:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
        }
    }
}

final class ContinuationBox<T>: @unchecked Sendable {
    var continuation: CheckedContinuation<T, Error>?
    private var _resumed = false
    let lock = NSLock()

    var isResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _resumed
    }

    func resume(throwing error: Error) {
        let cont: CheckedContinuation<T, Error>?
        lock.lock()
        guard !_resumed else { lock.unlock(); return }
        _resumed = true
        cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
    func resume(returning value: T) {
        let cont: CheckedContinuation<T, Error>?
        lock.lock()
        guard !_resumed else { lock.unlock(); return }
        _resumed = true
        cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}

func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let box = ContinuationBox<T>()
    var operationTask: Task<Void, Never>?
    let timeoutTask = Task {
        do {
            try await Task.sleep(for: .seconds(seconds))
            operationTask?.cancel()
            box.resume(throwing: CorrectionError.serverTimeout)
        } catch {
            // Timeout task cancelled, body already completed
        }
    }
    defer { timeoutTask.cancel(); operationTask?.cancel() }

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            box.lock.lock(); box.continuation = continuation; box.lock.unlock()
            guard !box.isResumed else { return }
            operationTask = Task {
                do {
                    let result = try await operation()
                    box.resume(returning: result)
                } catch {
                    box.resume(throwing: error)
                }
            }
        }
    } onCancel: {
        box.resume(throwing: CancellationError())
    }
}
