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
        let continuation: AsyncStream<Result<CorrectionResult, Error>>.Continuation
        let deadline: Date
        let overrideServiceType: ServiceType?
        let overrideCustomPrompt: CustomPrompt?
        let language: String

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
        language: String = ""
    ) async throws -> CorrectionResult {
        guard text.count <= Constants.maxTextLength else {
            throw CorrectionError.textTooLong(length: text.count, maxLength: Constants.maxTextLength)
        }

        let (stream, continuation) = AsyncStream<Result<CorrectionResult, Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let request = LLMRequest(
            text: text,
            promptType: type,
            priority: priority,
            continuation: continuation,
            deadline: Date().addingTimeInterval(60),
            overrideServiceType: overrideServiceType,
            overrideCustomPrompt: overrideCustomPrompt,
            language: language
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
        }
    }

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        
        while !queue.isEmpty {
            let request = queue.removeFirst()
            
            if Date() > request.deadline {
                request.continuation.yield(.failure(CorrectionError.serverTimeout))
                request.continuation.finish()
                continue
            }
            
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

                let promptType: PromptType
                if let customPrompt = request.overrideCustomPrompt {
                    promptType = .custom(name: customPrompt.name, template: customPrompt.template)
                } else {
                    promptType = request.promptType
                }

                if let cached = await CorrectionCache.shared.get(text: request.text, promptType: promptType.label, modelID: modelID) {
                    request.continuation.yield(.success(cached))
                    request.continuation.finish()
                    continue
                }

                let result = try await service.correct(text: request.text, promptType: promptType, language: request.language)
                await CorrectionCache.shared.set(result, text: request.text, promptType: promptType.label, modelID: modelID)
                request.continuation.yield(.success(result))
                request.continuation.finish()
            } catch {
                request.continuation.yield(.failure(error))
                request.continuation.finish()
            }
        }
        
        isProcessing = false
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
