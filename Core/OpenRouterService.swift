import Foundation
import os

final class OpenRouterService: LLMService, Sendable {
    static let shared = OpenRouterService()
    private let baseURLString = "https://openrouter.ai/api/v1/chat/completions"

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

    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult {
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: promptType,
            model: openRouterModel, url: try chatURL(), apiKey: apiKey,
            extraHeaders: ["HTTP-Referer": Constants.bundleID])
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: .fluency,
            model: openRouterModel, url: try chatURL(), apiKey: apiKey,
            extraHeaders: ["HTTP-Referer": Constants.bundleID])
    }

    func explain(original: String, corrected: String) async throws -> String {
        let engine = PromptEngine(language: resolvedLanguage)
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
                    let engine = PromptEngine(language: resolvedLanguage)
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
