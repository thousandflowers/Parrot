import Foundation

actor LocalLLMService: @preconcurrency LLMService {
    static let shared = LocalLLMService()

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

    private func localChatURL(port: Int) throws -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw CorrectionError.serverNotRunning
        }
        return url
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let port = try await ensureServerRunning()
        return try await performCorrection(text: text, promptType: promptType,
            model: modelName, url: try localChatURL(port: port), apiKey: nil)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let port = try await ensureServerRunning()
        return try await performCorrection(text: text, promptType: .fluency,
            model: modelName, url: try localChatURL(port: port), apiKey: nil)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: resolvedLanguage)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let port = try await ensureServerRunning()

        return try await performOpenAIRequest(
            body: chatBody(model: modelName, prompt: prompt, systemPrompt: nil, temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: try localChatURL(port: port),
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: resolvedLanguage)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let port = try await ensureServerRunning()

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: modelName, prompt: prompt, temperature: 0.1, stream: true),
                        url: try localChatURL(port: port),
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
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
