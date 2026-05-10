import Foundation

actor LocalLLMService: @preconcurrency LLMService {
    static let shared = LocalLLMService()

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }

    nonisolated private var modelName: String {
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
        return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local-qwen"
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 500, 502: throw CorrectionError.serverTimeout
        case 503: throw CorrectionError.serverNotRunning
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    private func ensureServerRunning() async throws -> Int {
        let port = await ServerManager.shared.currentPort
        if port > 0 { return port }

        guard let modelPath = ModelManager.shared.currentModelPath else {
            throw CorrectionError.serverNotRunning
        }
        let newPort = try await ServerManager.shared.ensureRunning(modelPath: modelPath)
        await ServerHealthMonitor.shared.startMonitoring()
        return newPort
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
        let port = try await ensureServerRunning()

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: modelName, prompt: prompt, temperature: 0.1),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: modelName, confidence: 0.9, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        let port = try await ensureServerRunning()

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: modelName, prompt: prompt, temperature: 0.3),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: modelName, confidence: 0.9, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let port = try await ensureServerRunning()

        return try await performOpenAIRequest(
            body: chatBody(model: modelName, prompt: prompt, systemPrompt: nil, temperature: 0.3, maxTokens: 512),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: language)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let port = try await ensureServerRunning()

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: modelName, prompt: prompt, temperature: 0.1, stream: true),
                        url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
                        apiKey: nil
                    )
                    var fullText = ""
                    for try await chunk in stream {
                        fullText += chunk
                        continuation.yield(fullText)
                    }
                    if fullText.isEmpty {
                        continuation.finish(throwing: CorrectionError.outputParsingFailed(raw: "empty"))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
