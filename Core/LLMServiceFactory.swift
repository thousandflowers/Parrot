import Foundation

struct LLMServiceFactory {
    static func make() -> LLMService {
        switch PreferencesStore.shared.serviceType {
        case .stub:   return StubLLMService.shared
        case .local:  return LocalLLMService.shared
        case .remote: return RemoteLLMService.shared
        }
    }
}
