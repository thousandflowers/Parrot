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
        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }
        let model = openAIModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.1),
            url: URL(string: "\(openAIBaseURL)/chat/completions")!,
            apiKey: apiKey
        )
        return CorrectionResult(original: text, corrected: corrected.isEmpty ? text : corrected,
                               modelID: model, confidence: 0.9, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }
        let model = openAIModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: 0.3),
            url: URL(string: "\(openAIBaseURL)/chat/completions")!,
            apiKey: apiKey
        )
        return CorrectionResult(original: text, corrected: corrected.isEmpty ? text : corrected,
                               modelID: model, confidence: 0.9, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }

        return try await performOpenAIRequest(
            body: chatBody(model: openAIModel, prompt: prompt, systemPrompt: nil, temperature: 0.3, maxTokens: 512),
            url: URL(string: "\(openAIBaseURL)/chat/completions")!,
            apiKey: apiKey
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
