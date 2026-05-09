import Foundation

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
        resolveServiceType(for: Constants.UserDefaultsKey.fluencyServiceType)
    }

    private static func resolveServiceType(for key: String) -> ServiceType {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let type = ServiceType(rawValue: raw) else { return .stub }
        return type
    }
}
