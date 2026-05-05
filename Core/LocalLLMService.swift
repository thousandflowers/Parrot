import Foundation

actor LocalLLMService: @preconcurrency LLMService {
    static let shared = LocalLLMService()

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 503: throw CorrectionError.serverNotRunning
        case 500: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: "local-qwen", prompt: prompt, temperature: 0.1),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
        return CorrectionResult(original: text, corrected: corrected.isEmpty ? text : corrected,
                               modelID: "local-qwen", confidence: 0.9, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: "local-qwen", prompt: prompt, temperature: 0.3),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
        return CorrectionResult(original: text, corrected: corrected.isEmpty ? text : corrected,
                               modelID: "local-qwen", confidence: 0.9, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let port = await ServerManager.shared.currentPort
        guard port > 0 else { throw CorrectionError.serverNotRunning }

        return try await performOpenAIRequest(
            body: chatBody(model: "local-qwen", prompt: prompt, systemPrompt: nil, temperature: 0.3, maxTokens: 512),
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!,
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let result = try await correct(text: text, promptType: promptType)
                    continuation.yield(result.correctedText)
                } catch {
                    continuation.yield("[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }
}
