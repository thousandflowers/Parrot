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
    case translation(targetLanguage: String)

    var label: String {
        switch self {
        case .grammar: "grammar"
        case .fluency: "fluency"
        case .explain: "explain"
        case .custom: "custom"
        case .translation(let lang): "translation:\(lang)"
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
            return "Il motore AI non è ancora pronto. Attendi qualche secondo e riprova."
        case .serverTimeout:
            return "Il server sta impiegando troppo tempo. Riprova tra qualche secondo."
        case .modelNotLoaded:
            return "Nessun modello installato. Vai su Impostazioni > Modelli per scaricarne uno."
        case .modelDownloadFailed:
            return "Download fallito. Controlla la connessione. Se il problema persiste, aggiungi un token HuggingFace in Impostazioni > Avanzate."
        case .modelCorrupted:
            return "Il file del modello è danneggiato. Scaricalo di nuovo dal pannello Modelli."
        case .modelIncompatibleVersion:
            return "Questo modello non è compatibile con la versione attuale. Scarica un modello aggiornato."
        case .outOfMemory:
            return "Memoria insufficiente. Chiudi altre app o scegli un modello più piccolo nel pannello Modelli."
        case .networkUnavailable:
            return "Connessione assente. Controlla il Wi-Fi o il cavo ethernet."
        case .invalidAPIKey:
            return "API Key non valida. Verificala in Impostazioni > Motore."
        case .rateLimited:
            return "Troppe richieste. Riprova tra qualche secondo."
        case .outputParsingFailed:
            return "Il modello ha prodotto una risposta inattesa. Riprova la correzione."
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
