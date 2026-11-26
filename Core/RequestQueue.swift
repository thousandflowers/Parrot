import Foundation

actor RequestQueue {
    static let shared = RequestQueue()

    private var queue: [LLMRequest] = []
    private var isProcessing = false
    private var lastAutoCheckProcessed = Date.distantPast
    /// The request currently talking to the backend, so a cancelled caller can stop it
    /// instead of leaving it to occupy the single-slot local server.
    private var inFlight: (id: UUID, task: Task<Void, Never>)?

    struct LLMRequest {
        let id: UUID
        let text: String
        let promptType: PromptType
        let priority: Priority
        let continuation: AsyncStream<Result<CorrectionResult, Error>>.Continuation
        let deadline: Date
        let overrideServiceType: ServiceType?
        let overrideCustomPrompt: CustomPrompt?
        let language: String
        /// Added to the real prompt (e.g. knowledge-base context); never replaces it.
        let extraInstruction: String?

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
        overrideCustomPrompt: CustomPrompt? = nil,
        language: String = "",
        extraInstruction: String? = nil
    ) async throws -> CorrectionResult {
        guard text.count <= Constants.maxTextLength else {
            throw CorrectionError.textTooLong(length: text.count, maxLength: Constants.maxTextLength)
        }

        let (stream, continuation) = AsyncStream<Result<CorrectionResult, Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let requestID = UUID()
        let request = LLMRequest(
            id: requestID,
            text: text,
            promptType: type,
            priority: priority,
            continuation: continuation,
            deadline: Date().addingTimeInterval(Constants.queueTimeout),
            overrideServiceType: overrideServiceType,
            overrideCustomPrompt: overrideCustomPrompt,
            language: language,
            extraInstruction: extraInstruction
        )
        if let insertAt = self.queue.firstIndex(where: { $0.priority < priority }) {
            self.queue.insert(request, at: insertAt)
        } else {
            self.queue.append(request)
        }
        Task { await self.processQueue() }

        return try await withTaskCancellationHandler {
            for await result in stream {
                return try result.get()
            }
            throw CancellationError()
        } onCancel: {
            continuation.finish()
            Task { await self.cancel(requestID: requestID) }
        }
    }

    /// Drops a still-queued request, or stops the in-flight one.
    private func cancel(requestID: UUID) {
        if let index = queue.firstIndex(where: { $0.id == requestID }) {
            queue.remove(at: index).continuation.finish()
            return
        }
        if let current = inFlight, current.id == requestID {
            current.task.cancel()
        }
    }

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true

        while !queue.isEmpty {
            // Starvation guard: if no .autoCheck has been processed in 3 seconds,
            // bump the oldest .autoCheck to the front so it doesn't wait forever.
            if queue.contains(where: { $0.priority == .autoCheck }),
               Date().timeIntervalSince(lastAutoCheckProcessed) > 3 {
                if let idx = queue.firstIndex(where: { $0.priority == .autoCheck }) {
                    let bumped = queue.remove(at: idx)
                    queue.insert(bumped, at: 0)
                }
            }
            let request = queue.removeFirst()
            if request.priority == .autoCheck { lastAutoCheckProcessed = Date() }

            if Date() > request.deadline {
                request.continuation.yield(.failure(CorrectionError.serverTimeout))
                request.continuation.finish()
                continue
            }

            let work = Task { await self.run(request) }
            inFlight = (request.id, work)
            await work.value
            inFlight = nil
        }

        isProcessing = false
    }

    private func run(_ request: LLMRequest) async {
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

        let promptType: PromptType
        if let customPrompt = request.overrideCustomPrompt {
            switch request.promptType {
            case .grammar, .fluency, .coach, .aiPrompt, .deSlop:
                promptType = .custom(name: customPrompt.name, template: customPrompt.template)
            default:
                promptType = request.promptType
            }
        } else {
            promptType = request.promptType
        }
        let cacheKey = promptType.cacheKey(extraInstruction: request.extraInstruction)
        let correct: @Sendable (_ model: String?) async throws -> CorrectionResult = { model in
            try await PromptContext.$extraInstruction.withValue(request.extraInstruction) {
                try await PromptContext.$modelOverride.withValue(model) {
                    try await service.correct(text: request.text, promptType: promptType, language: request.language)
                }
            }
        }

        if let cached = await CorrectionCache.shared.get(text: request.text, promptType: cacheKey, modelID: modelID, language: request.language) {
            finish(request, with: .success(cached))
            return
        }

        do {
            let result = try await correct(nil)
            await CorrectionCache.shared.set(result, text: request.text, promptType: cacheKey, modelID: modelID, language: request.language)
            finish(request, with: .success(result))
        } catch {
            // A cancelled request must not start fallback work on the shared backend.
            guard !Task.isCancelled, !(error is CancellationError) else {
                finish(request, with: .failure(CancellationError()))
                return
            }
            if let fallback = await fallbackResult(for: request, error: error, serviceType: serviceType,
                                                   modelID: modelID, promptType: promptType,
                                                   cacheKey: cacheKey, correct: correct) {
                finish(request, with: .success(fallback))
                return
            }
            finish(request, with: .failure(error))
        }
    }

    /// Retry with the configured fallback model (passed explicitly, Settings are never
    /// rewritten), then Apple Intelligence when the local server is unavailable.
    private func fallbackResult(
        for request: LLMRequest,
        error: Error,
        serviceType: ServiceType,
        modelID: String,
        promptType: PromptType,
        cacheKey: String,
        correct: @Sendable (_ model: String?) async throws -> CorrectionResult
    ) async -> CorrectionResult? {
        guard let corrError = error as? CorrectionError, corrError.isRetryable else { return nil }
        if let fallbackModelID = LLMServiceFactory.resolveFallbackModelID(for: serviceType),
           !fallbackModelID.isEmpty, fallbackModelID != modelID,
           let fallbackResult = try? await correct(fallbackModelID) {
            await CorrectionCache.shared.set(fallbackResult, text: request.text, promptType: cacheKey, modelID: fallbackModelID, language: request.language)
            return fallbackResult
        }
        guard !Task.isCancelled, serviceType == .local || serviceType == .ollama else { return nil }
        if #available(macOS 26.0, *), AppleIntelligenceService.shared.isAvailable {
            return try? await PromptContext.$extraInstruction.withValue(request.extraInstruction) {
                try await AppleIntelligenceService.shared.correct(
                    text: request.text, promptType: promptType, language: request.language)
            }
        }
        return nil
    }

    private func finish(_ request: LLMRequest, with result: Result<CorrectionResult, Error>) {
        request.continuation.yield(result)
        request.continuation.finish()
    }

    // nonisolated is safe here — delegates to a pure static factory method with no actor state.
    private nonisolated func resolveModelID(for serviceType: ServiceType) -> String {
        LLMServiceFactory.resolveModelID(for: serviceType)
    }
}

func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CorrectionError.serverTimeout
        }

        guard let result = try await group.next() else {
            throw CancellationError()
        }
        group.cancelAll()
        return result
    }
}
