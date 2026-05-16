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
    case coach
    case translation(targetLanguage: String)
    case custom(name: String, template: String)

    var label: String {
        switch self {
        case .grammar: "grammar"
        case .fluency: "fluency"
        case .explain: "explain"
        case .coach: "coach"
        case .translation: "translation"
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
    case textTooLong(length: Int, maxLength: Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibilità non abilitata. Vai in Preferenze di Sistema > Privacy e sicurezza > Accessibilità."
        case .noTextSelected:
            return "Nessun testo selezionato. Seleziona del testo e riprova."
        case .textExtractionFailed(let appName):
            return "Impossibile leggere il testo da \(appName)."
        case .serverNotRunning:
            return "Il motore AI è offline. Controlla il servizio selezionato nelle impostazioni."
        case .serverTimeout:
            return "Timeout del server. Riprova tra qualche secondo."
        case .modelNotLoaded:
            return "Modello non caricato. Verifica che sia installato correttamente."
        case .modelDownloadFailed(let url):
            return "Download fallito da \(url.host ?? url.absoluteString). Il modello potrebbe richiedere autenticazione — prova un modello diverso dal catalogo."
        case .modelCorrupted(let sha):
            return "Modello corrotto (SHA: \(sha.prefix(12))...). Scarica di nuovo il modello."
        case .outOfMemory:
            return "Memoria insufficiente. Chiudi altre app o usa un modello piu piccolo."
        case .networkUnavailable:
            return "Connessione di rete non disponibile."
        case .invalidAPIKey:
            return "API Key non valida. Verifica le impostazioni."
        case .rateLimited:
            return "Troppe richieste. Attendi qualche secondo."
        case .outputParsingFailed(let raw):
            return "Risposta AI non valida (\(raw.prefix(30))...). Riprova."
        case .textTooLong(let length, let maxLength):
            return "Testo troppo lungo (\(length) caratteri). Massimo: \(maxLength)."
        }
    }
}

protocol LLMService: AnyObject, Sendable {
    func correct(text: String, promptType: PromptType) async throws -> CorrectionResult
    func correctFluency(text: String) async throws -> CorrectionResult
    func explain(original: String, corrected: String) async throws -> String
    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error>
    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws
}

/// Sottoprotocoolo per i servizi reali (Local, Remote, Ollama, OpenRouter).
/// Implementando i 4 metodi di configurazione si ottengono gratis
/// correct/correctFluency/explain/streamCorrect via extension default.
protocol LLMServiceBase: LLMService {
    func resolveURL() async throws -> URL
    func resolveAPIKey() async throws -> String?
    var resolvedModel: String { get }
    var extraServiceHeaders: [String: String] { get }
}
