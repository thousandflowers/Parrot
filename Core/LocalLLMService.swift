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

    func warmup() async {
        _ = try? await ensureServerRunning()
    }

    private func ensureServerRunning() async throws -> Int {
        let port = await ServerManager.shared.currentPort
        if port > 0 { return port }

        guard let modelPath = await ModelManager.shared.getCurrentModelPath() else {
            throw CorrectionError.modelNotLoaded
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

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let port = try await ensureServerRunning()
        let isGrammar = promptType == .grammar || promptType == .grammarAndFluency
        let sampling = isGrammar ? Constants.localGrammarSampling : Constants.localFluencySampling
        let samples = isGrammar ? Constants.localSelfConsistencyPasses : 1
        return try await performCorrection(text: text, promptType: promptType, language: language,
            model: modelName, url: try localChatURL(port: port), apiKey: nil,
            sampling: sampling, samples: samples)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let port = try await ensureServerRunning()
        return try await performCorrection(text: text, promptType: .fluency,
            model: modelName, url: try localChatURL(port: port), apiKey: nil,
            sampling: Constants.localFluencySampling)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: corrected, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
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
                    let port = try await self.ensureServerRunning()
                    let url = try self.localChatURL(port: port)
                    let streamSampling = (promptType == .grammar || promptType == .grammarAndFluency)
                        ? Constants.localGrammarSampling : Constants.localFluencySampling
                    for try await accumulated in self.defaultStreamCorrect(text: text, promptType: promptType, model: self.modelName, url: url, apiKey: nil, sampling: streamSampling) {
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
