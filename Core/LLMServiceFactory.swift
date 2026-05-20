import Foundation
import OSLog

struct LLMServiceFactory {
    static func make() -> LLMService {
        make(with: resolveDefaultServiceType())
    }

    static func resolveDefaultServiceType() -> ServiceType {
        resolveServiceType(for: Constants.UserDefaultsKey.serviceType)
    }

    static func make(with serviceType: ServiceType) -> LLMService {
        switch serviceType {
        case .stub:       return StubLLMService.shared
        case .local:      return LocalLLMService.shared
        case .remote:     return RemoteLLMService.shared
        case .ollama:     return OllamaService.shared
        case .openRouter: return OpenRouterService.shared
        }
    }

    static func resolveFluencyServiceType() -> ServiceType {
        let type = resolveServiceType(for: Constants.UserDefaultsKey.fluencyServiceType)
        return type == .stub ? resolveDefaultServiceType() : type
    }

    static func resolveServiceType(forPromptType promptType: PromptType) -> ServiceType {
        switch promptType {
        case .fluency:
            return resolveFluencyServiceType()
        default:
            return resolveDefaultServiceType()
        }
    }

    private static func resolveServiceType(for key: String) -> ServiceType {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let type = ServiceType(rawValue: raw) else {
            Logger.infra.warning("No serviceType configured for \(key), defaulting to .local")
            return .local
        }
        return type
    }

    static func resolveModelID(for serviceType: ServiceType) -> String {
        switch serviceType {
        case .stub:
            return "stub-v1"
        case .local:
            let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)
            return id?.replacingOccurrences(of: ".gguf", with: "") ?? "local-qwen"
        case .remote:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini"
        case .ollama:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2"
        case .openRouter:
            return UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
        }
    }
}
