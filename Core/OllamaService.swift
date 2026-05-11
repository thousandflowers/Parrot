import Foundation

final class OllamaService: LLMService, Sendable {
    static let shared = OllamaService()

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }
    nonisolated private var ollamaBaseURL: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaBaseURL) ?? "http://localhost:11434"
    }
    nonisolated private var ollamaModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2"
    }

    private func chatURL() throws -> URL {
        let base = ollamaBaseURL.hasSuffix("/") ? String(ollamaBaseURL.dropLast()) : ollamaBaseURL
        guard let url = URL(string: "\(base)/v1/chat/completions") else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 404: throw CorrectionError.modelNotLoaded
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
        let model = ollamaModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.1),
            url: try chatURL(),
            apiKey: nil
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: 0.9, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        let model = ollamaModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.3),
            url: try chatURL(),
            apiKey: nil
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: 0.9, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let model = ollamaModel

        return try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, systemPrompt: nil, temperature: 0.3, maxTokens: 512),
            url: try chatURL(),
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: language)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let model = ollamaModel

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: model, prompt: prompt, temperature: 0.1, stream: true),
                        url: try chatURL(),
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
