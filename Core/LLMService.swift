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
    case coach
    case explain
    case custom(name: String, template: String)
    case translation(targetLanguage: String)

    var label: String {
        switch self {
        case .grammar: "grammar"
        case .fluency: "fluency"
        case .coach: "coach"
        case .explain: "explain"
        case .custom: "custom"
        case .translation(let lang): "translation:\(lang)"
        }
    }

    var isFluency: Bool {
        if case .fluency = self { return true }
        return false
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
            return "Accessibility not enabled. Open System Settings > Privacy & Security > Accessibility and add Parrot."
        case .noTextSelected:
            return "No text selected. Select some text and try again."
        case .textExtractionFailed(let appName):
            return "Cannot read text from \(appName). The app may not support Accessibility."
        case .serverNotRunning:
            return "AI engine failed to start. Check that llama-server is installed or restart the app."
        case .serverTimeout:
            return "Server is taking too long to respond. Try again in a few seconds."
        case .modelNotLoaded:
            return "No model installed. Go to Settings › Models to download one."
        case .modelDownloadFailed:
            return "Download failed. Check your connection. If the issue persists, add a HuggingFace token in Settings › Advanced."
        case .modelCorrupted:
            return "Model file is corrupted. Download it again from the Models panel."
        case .modelIncompatibleVersion:
            return "This model is not compatible with the current version. Download an updated model."
        case .outOfMemory:
            return "Not enough memory. Close other apps or choose a smaller model in the Models panel."
        case .networkUnavailable:
            return "No connection. Check your Wi-Fi or ethernet cable."
        case .invalidAPIKey:
            return "Invalid API key. Verify it in Settings › Engine."
        case .rateLimited:
            return "Too many requests. Try again in a few seconds."
        case .outputParsingFailed:
            return "The model produced an unexpected response. Try the correction again."
        case .textTooLong(let length, let maxLength):
            return "Text too long (\(length) characters). Maximum: \(maxLength)."
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
