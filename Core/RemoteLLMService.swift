import Foundation

final class RemoteLLMService: LLMService, Sendable {
    static let shared = RemoteLLMService()

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }
    nonisolated private var openAIBaseURL: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIBaseURL) ?? "https://api.openai.com/v1"
    }
    nonisolated private var openAIModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
    }

    private func chatURL() throws -> URL {
        guard let url = URL(string: "\(openAIBaseURL)/chat/completions") else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 401, 403: throw CorrectionError.invalidAPIKey
        case 429: throw CorrectionError.rateLimited
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
        guard let apiKey = try? KeychainService.shared.load(for: "openai"), !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }
        let model = openAIModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.1),
            url: try chatURL(),
            apiKey: apiKey
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: 0.9, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        guard let apiKey = try? KeychainService.shared.load(for: "openai"), !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }
        let model = openAIModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.3),
            url: try chatURL(),
            apiKey: apiKey
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: 0.9, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        guard let apiKey = try? KeychainService.shared.load(for: "openai"), !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }

        return try await performOpenAIRequest(
            body: chatBody(model: openAIModel, prompt: prompt, systemPrompt: nil, temperature: 0.3, maxTokens: 512),
            url: try chatURL(),
            apiKey: apiKey
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: language)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    guard let apiKey = try? KeychainService.shared.load(for: "openai"), !apiKey.isEmpty else {
                        throw CorrectionError.invalidAPIKey
                    }
                    let model = openAIModel

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: model, prompt: prompt, temperature: 0.1, stream: true),
                        url: try chatURL(),
                        apiKey: apiKey
                    )
                    var fullText = ""
                    for try await chunk in stream {
                        fullText += chunk
                        continuation.yield(fullText)
                    }
                    if fullText.isEmpty {
                        continuation.yield(text)
                    }
                    continuation.finish()
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
