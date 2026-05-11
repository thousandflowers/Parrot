import Foundation
import os

final class OpenRouterService: LLMService, Sendable {
    static let shared = OpenRouterService()
    private let baseURLString = "https://openrouter.ai/api/v1/chat/completions"

    nonisolated private var language: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? "it"
    }
    nonisolated private var openRouterModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
    }
    private let apiKeyLock = NSLock()
    private nonisolated(unsafe) var _cachedAPIKey: String?
    private nonisolated(unsafe) var _lastAPIKeyTime: Date = .distantPast

    private func openRouterAPIKey() -> String {
        let now = Date()
        apiKeyLock.lock()
        defer { apiKeyLock.unlock() }
        if let cached = _cachedAPIKey, now.timeIntervalSince(_lastAPIKeyTime) < 60 {
            return cached
        }
        let key: String
        do {
            key = try KeychainService.shared.load(for: "openrouter")
        } catch {
            os_log(.debug, "Keychain load openrouter: %{public}@", error.localizedDescription)
            key = ""
        }
        if !key.isEmpty {
            _cachedAPIKey = key
            _lastAPIKeyTime = now
        }
        return key
    }

    private func chatURL() throws -> URL {
        guard let url = URL(string: baseURLString) else {
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
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }
        let model = openRouterModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: Constants.grammarTemperature),
            url: try chatURL(),
            apiKey: apiKey,
            extraHeaders: ["HTTP-Referer": Constants.bundleID]
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: Constants.defaultConfidence, promptType: promptType.label)
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildFluencyPrompt(for: text, customInstruction: nil)
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }
        let model = openRouterModel

        let corrected = try await performOpenAIRequest(
            body: chatBody(model: model, prompt: prompt, temperature: Constants.fluencyTemperature),
            url: try chatURL(),
            apiKey: apiKey,
            extraHeaders: ["HTTP-Referer": Constants.bundleID]
        )
        guard !corrected.isEmpty else { throw CorrectionError.outputParsingFailed(raw: "empty") }
        return CorrectionResult(original: text, corrected: corrected,
                               modelID: model, confidence: Constants.defaultConfidence, promptType: "fluency")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: language)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else {
            throw CorrectionError.invalidAPIKey
        }

        return try await performOpenAIRequest(
            body: chatBody(model: openRouterModel, prompt: prompt, systemPrompt: nil, temperature: Constants.fluencyTemperature, maxTokens: Constants.explainMaxTokens),
            url: try chatURL(),
            apiKey: apiKey,
            extraHeaders: ["HTTP-Referer": Constants.bundleID]
        )
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let engine = PromptEngine(language: language)
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)
                    let apiKey = openRouterAPIKey()
                    guard !apiKey.isEmpty else {
                        throw CorrectionError.invalidAPIKey
                    }

                    let stream = performOpenAIStreamRequest(
                        body: chatBody(model: openRouterModel, prompt: prompt, temperature: 0.1, stream: true),
                        url: try chatURL(),
                        apiKey: apiKey,
                        extraHeaders: ["HTTP-Referer": Constants.bundleID]
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
