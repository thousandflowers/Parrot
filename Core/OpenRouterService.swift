import Foundation
import OSLog

final class OpenRouterService: LLMService, Sendable {
    static let shared = OpenRouterService()
    private let baseURLString = "https://openrouter.ai/api/v1/chat/completions"

    nonisolated private var openRouterModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
    }

    private func openRouterAPIKey() -> String {
        do {
            return try KeychainService.shared.load(for: "openrouter")
        } catch KeychainError.itemNotFound {
            return ""
        } catch {
            Logger.core.error("OpenRouterService: keychain error — \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    private func chatURL() throws -> URL {
        guard let url = URL(string: baseURLString) else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let apiKey = openRouterAPIKey()
        guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
        return try await performCorrection(text: text, promptType: promptType, language: language,
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
        let lang = LanguageDetector.detect(text: corrected, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
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
                    let apiKey = self.openRouterAPIKey()
                    guard !apiKey.isEmpty else { throw CorrectionError.invalidAPIKey }
                    let url = try self.chatURL()
                    let extraHeaders = ["HTTP-Referer": Constants.bundleID]
                    for try await accumulated in self.defaultStreamCorrect(text: text, promptType: promptType, model: self.openRouterModel, url: url, apiKey: apiKey, extraHeaders: extraHeaders) {
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
