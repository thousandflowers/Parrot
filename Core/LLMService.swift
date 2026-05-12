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
            return "Accessibilità non abilitata. Apri Impostazioni di Sistema > Privacy e sicurezza > Accessibilità e aggiungi RefineClone all'elenco."
        case .noTextSelected:
            return "Nessun testo selezionato. Seleziona del testo e riprova."
        case .textExtractionFailed(let appName):
            return "Impossibile leggere il testo da \(appName). L'app potrebbe non supportare l'Accessibilità."
        case .serverNotRunning:
            return "Il motore AI è offline. Riavvio in corso..."
        case .serverTimeout:
            return "Il server sta impiegando troppo tempo. Riprova tra qualche secondo."
        case .modelNotLoaded:
            return "Modello non caricato. Verifica nelle impostazioni Modelli che sia installato."
        case .modelDownloadFailed:
            return "Impossibile scaricare il modello. Controlla la connessione e riprova."
        case .modelCorrupted:
            return "Il file del modello è danneggiato. Scaricalo di nuovo dal pannello Modelli."
        case .modelIncompatibleVersion:
            return "Il formato del modello non è compatibile. Scarica un modello aggiornato dal pannello Modelli."
        case .outOfMemory:
            return "Memoria insufficiente. Chiudi altre app o usa un modello più piccolo."
        case .networkUnavailable:
            return "Connessione di rete non disponibile. Controlla il Wi-Fi o la connessione ethernet."
        case .invalidAPIKey:
            return "API Key non valida. Controllala nelle impostazioni del servizio."
        case .rateLimited:
            return "Troppe richieste. Attendi qualche secondo e riprova."
        case .outputParsingFailed:
            return "La risposta ricevuta non è nel formato atteso. Riprova."
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
