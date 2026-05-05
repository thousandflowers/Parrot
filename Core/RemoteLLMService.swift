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

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let fullPrompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }

        let model = openAIModel
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful writing assistant. Follow the user instructions exactly."],
                ["role": "user", "content": fullPrompt]
            ],
            "temperature": 0.1,
            "max_tokens": 1024,
            "stream": false
        ]

        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw CorrectionError.networkUnavailable }
        switch httpResponse.statusCode {
        case 200: break
        case 401, 403: throw CorrectionError.invalidAPIKey
        case 429: throw CorrectionError.rateLimited
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(httpResponse.statusCode)")
        }

        let corrected = try parseResponse(data: data)
        return CorrectionResult(
            original: text,
            corrected: corrected.isEmpty ? text : corrected,
            modelID: model,
            confidence: 0.9,
            promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let fluencyPrompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)

        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }

        let model = openAIModel
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful writing assistant. Follow the user instructions exactly."],
                ["role": "user", "content": fluencyPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 1024,
            "stream": false
        ]

        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw CorrectionError.networkUnavailable }
        switch httpResponse.statusCode {
        case 200: break
        case 401, 403: throw CorrectionError.invalidAPIKey
        case 429: throw CorrectionError.rateLimited
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(httpResponse.statusCode)")
        }

        let corrected = try parseResponse(data: data)
        return CorrectionResult(
            original: text,
            corrected: corrected.isEmpty ? text : corrected,
            modelID: model,
            confidence: 0.9,
            promptType: "fluency"
        )
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let explainPrompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)

        let apiKey: String
        do { apiKey = try KeychainService.shared.load(for: "openai") }
        catch { throw CorrectionError.invalidAPIKey }

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [["role": "user", "content": explainPrompt]],
            "temperature": 0.3,
            "max_tokens": 512,
            "stream": false
        ]
        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        let request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CorrectionError.serverTimeout
        }
        return try parseResponse(data: data)
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
