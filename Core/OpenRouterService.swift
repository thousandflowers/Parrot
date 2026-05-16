import Foundation
import os

final class OpenRouterService: LLMServiceBase, Sendable {
    static let shared = OpenRouterService()
    private let endpointURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    var resolvedModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel)
            ?? "openai/gpt-4o-mini"
    }

    var extraServiceHeaders: [String: String] {
        ["HTTP-Referer": Constants.bundleID]
    }

    func resolveURL() async throws -> URL { endpointURL }

    func resolveAPIKey() async throws -> String? {
        do {
            let key = try KeychainService.shared.load(for: "openrouter")
            guard !key.isEmpty else { throw CorrectionError.invalidAPIKey }
            return key
        } catch {
            os_log(.debug, "Keychain load openrouter: %{public}@", error.localizedDescription)
            throw CorrectionError.invalidAPIKey
        }
    }
}
