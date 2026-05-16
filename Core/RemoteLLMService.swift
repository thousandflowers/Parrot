import Foundation
import os

final class RemoteLLMService: LLMServiceBase, Sendable {
    static let shared = RemoteLLMService()

    var resolvedModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
    }

    var extraServiceHeaders: [String: String] { [:] }

    func resolveURL() async throws -> URL {
        let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIBaseURL)
                  ?? "https://api.openai.com/v1"
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    func resolveAPIKey() async throws -> String? {
        do {
            let key = try KeychainService.shared.load(for: "openai")
            guard !key.isEmpty else { throw CorrectionError.invalidAPIKey }
            return key
        } catch {
            os_log(.debug, "Keychain load openai: %{public}@", error.localizedDescription)
            throw CorrectionError.invalidAPIKey
        }
    }
}
