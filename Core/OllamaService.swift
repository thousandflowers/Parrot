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

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        try await performCorrection(text: text, promptType: promptType, language: language,
            model: ollamaModel, url: try chatURL(), apiKey: nil)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await performCorrection(text: text, promptType: .fluency,
            model: ollamaModel, url: try chatURL(), apiKey: nil)
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: original, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let model = ollamaModel

        return try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, systemPrompt: nil, temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: try chatURL(),
            apiKey: nil
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        guard let url = try? chatURL() else {
            return AsyncThrowingStream { $0.finish(throwing: CorrectionError.networkUnavailable) }
        }
        return defaultStreamCorrect(text: text, promptType: promptType, model: ollamaModel, url: url, apiKey: nil)
    }
}
