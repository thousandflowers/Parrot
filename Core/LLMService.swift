import Foundation

enum ServiceType: String, Codable, CaseIterable {
    case stub
    case local
    case remote
    case ollama
    case openRouter
}

enum PromptType: Sendable {
    case grammar
    case fluency
    case explain
    case custom(name: String, template: String)

    var label: String {
        switch self {
        case .grammar: "grammar"
        case .fluency: "fluency"
        case .explain: "explain"
        case .custom: "custom"
        }
    }
}

enum CorrectionError: Error, LocalizedError, Sendable {
    case accessibilityPermissionDenied
    case noTextSelected
    case textExtractionFailed(appName: String)
    case serverNotRunning
    case serverTimeout
    case modelNotLoaded
    case modelDownloadFailed(url: URL)
    case modelCorrupted(expectedSHA: String)
    case outOfMemory
    case networkUnavailable
    case invalidAPIKey
    case rateLimited
    case outputParsingFailed(raw: String)
    case outputTooLong
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibilita non abilitata. Vai in Preferenze di Sistema > Privacy e sicurezza > Accessibilita."
        case .noTextSelected:
            return "Nessun testo selezionato. Seleziona del testo e riprova."
        case .serverNotRunning:
            return "Il motore AI e offline. Riavvio in corso..."
        case .outOfMemory:
            return "Memoria insufficiente. Chiudi altre app o usa un modello piu piccolo."
        case .invalidAPIKey:
            return "API Key non valida. Verifica le impostazioni."
        case .rateLimited:
            return "Troppe richieste. Attendi qualche secondo."
        default:
            return "Errore imprevisto. Riprova."
        }
    }
}

protocol LLMService: AnyObject, Sendable {
    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult
    func correctFluency(text: String) async throws -> CorrectionResult
    func explain(original: String, corrected: String) async throws -> String
    func streamCorrect(text: String, promptType: PromptType) -> AsyncStream<String>
}
