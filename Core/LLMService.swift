import Foundation

enum ServiceType: String, Codable, CaseIterable {
    case stub
    case local
    case remote
    case ollama
    case openRouter
    case appleIntelligence
}

enum PromptType: Sendable, Codable, Equatable, Hashable {
    case grammar
    case fluency
    case coach
    case explain
    case custom(name: String, template: String)
    case translation(targetLanguage: String)
    case deSlop
    case aiPrompt

    var label: String {
        switch self {
        case .grammar: "grammar"
        case .fluency: "fluency"
        case .coach: "coach"
        case .explain: "explain"
        case .custom: "custom"
        case .translation(let lang): "translation:\(lang)"
        case .deSlop: "deSlop"
        case .aiPrompt: "aiPrompt"
        }
    }

    var isFluency: Bool {
        if case .fluency = self { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case grammar, fluency, coach, explain, custom, translation, deSlop, aiPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let _ = try? container.decodeNil(forKey: .grammar) { self = .grammar; return }
        if let _ = try? container.decodeNil(forKey: .fluency) { self = .fluency; return }
        if let _ = try? container.decodeNil(forKey: .coach) { self = .coach; return }
        if let _ = try? container.decodeNil(forKey: .explain) { self = .explain; return }
        if let custom = try? container.decode(NestedCustom.self, forKey: .custom) {
            self = .custom(name: custom.name, template: custom.template); return
        }
        if let translation = try? container.decode(NestedTranslation.self, forKey: .translation) {
            self = .translation(targetLanguage: translation.targetLanguage); return
        }
        if let _ = try? container.decodeNil(forKey: .deSlop) { self = .deSlop; return }
        if let _ = try? container.decodeNil(forKey: .aiPrompt) { self = .aiPrompt; return }
        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "Unknown PromptType"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .grammar: try container.encodeNil(forKey: .grammar)
        case .fluency: try container.encodeNil(forKey: .fluency)
        case .coach: try container.encodeNil(forKey: .coach)
        case .explain: try container.encodeNil(forKey: .explain)
        case .custom(let name, let template):
            try container.encode(NestedCustom(name: name, template: template), forKey: .custom)
        case .translation(let targetLanguage):
            try container.encode(NestedTranslation(targetLanguage: targetLanguage), forKey: .translation)
        case .deSlop: try container.encodeNil(forKey: .deSlop)
        case .aiPrompt: try container.encodeNil(forKey: .aiPrompt)
        }
    }

    private struct NestedCustom: Codable { let name: String, template: String }
    private struct NestedTranslation: Codable { let targetLanguage: String }
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

    var isRetryable: Bool {
        switch self {
        case .serverTimeout, .networkUnavailable, .modelNotLoaded, .serverNotRunning:
            return true
        default:
            return false
        }
    }

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
    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult
    func correctFluency(text: String) async throws -> CorrectionResult
    func explain(original: String, corrected: String) async throws -> String
    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error>
    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws
}
