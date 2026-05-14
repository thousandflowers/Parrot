import Foundation

final class OllamaService: LLMService, Sendable {
    static let shared = OllamaService()

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
        try await performCorrection(text: text, promptType: promptType,
            model: ollamaModel, url: try chatURL(), apiKey: nil)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await performCorrection(text: text, promptType: .fluency,
            model: ollamaModel, url: try chatURL(), apiKey: nil)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: resolvedLanguage)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let model = ollamaModel

        return try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, systemPrompt: nil, temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: try chatURL(),
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: resolvedLanguage)
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
