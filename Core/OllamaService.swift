import Foundation

final class OllamaService: LLMServiceBase, Sendable {
    static let shared = OllamaService()

    var resolvedModel: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2"
    }

    var extraServiceHeaders: [String: String] { [:] }

    func resolveURL() async throws -> URL {
        let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaBaseURL)
                  ?? "http://localhost:11434"
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        guard let url = URL(string: "\(base)/v1/chat/completions") else {
            throw CorrectionError.networkUnavailable
        }
        return url
    }

    func resolveAPIKey() async throws -> String? { nil }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200:           return
        case 404:           throw CorrectionError.modelNotLoaded
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default:            throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }
}
