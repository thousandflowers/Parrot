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
    case modelIncompatibleVersion(path: String)
    case outOfMemory
    case networkUnavailable
    case invalidAPIKey
    case rateLimited
    case outputParsingFailed(raw: String)
    case textTooLong(length: Int, maxLength: Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibilita non abilitata. Vai in Preferenze di Sistema > Privacy e sicurezza > Accessibilita."
        case .noTextSelected:
            return "Nessun testo selezionato. Seleziona del testo e riprova."
        case .textExtractionFailed(let appName):
            return "Impossibile leggere il testo da \(appName)."
        case .serverNotRunning:
            return "Il motore AI e offline. Riavvio in corso..."
        case .serverTimeout:
            return "Timeout del server. Riprova tra qualche secondo."
        case .modelNotLoaded:
            return "Modello non caricato. Verifica che sia installato correttamente."
        case .modelDownloadFailed(let url):
            return "Download del modello fallito da \(url.host ?? url.absoluteString)."
        case .modelCorrupted(let sha):
            return "Modello corrotto (SHA: \(sha.prefix(12))...). Scarica di nuovo il modello."
        case .modelIncompatibleVersion:
            return "Versione GGUF del modello non compatibile. Scarica un modello aggiornato."
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
