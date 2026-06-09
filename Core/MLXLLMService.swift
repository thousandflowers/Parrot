import Foundation
import OSLog
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// LLM service backed by Apple MLX (mlx-swift) — typically 2-3× faster than llama.cpp on
/// Apple Silicon for the correction/chat path. Models are mlx-community Hugging Face repos,
/// downloaded on first use and cached by MLXLMCommon's hub layer; no ModelManager involvement.
actor MLXLLMService: @preconcurrency LLMService {
    static let shared = MLXLLMService()

    static let defaultModelID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    /// Curated MLX repos shown in Settings → Models. Mirrors ModelCatalog's GGUF tiers.
    struct CatalogEntry: Identifiable, Equatable {
        let id: String       // Hugging Face repo id
        let name: String
        let sizeLabel: String
        let ramRequired: Int // GB
    }

    static let catalog: [CatalogEntry] = [
        .init(id: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", name: "Qwen 2.5 0.5B (MLX)", sizeLabel: "~300 MB", ramRequired: 1),
        .init(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit", name: "Qwen 2.5 1.5B (MLX)", sizeLabel: "~1 GB", ramRequired: 2),
        .init(id: "mlx-community/Llama-3.2-1B-Instruct-4bit", name: "Llama 3.2 1B (MLX)", sizeLabel: "~700 MB", ramRequired: 2),
        .init(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B (MLX)", sizeLabel: "~1.8 GB", ramRequired: 3),
        .init(id: "mlx-community/gemma-2-2b-it-4bit", name: "Gemma 2 2B (MLX)", sizeLabel: "~1.5 GB", ramRequired: 3),
    ]

    private let maxTokens = 1024

    private var container: ModelContainer?
    private var loadedModelID: String?

    nonisolated var selectedModelID: String {
        let stored = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedMLXModelID) ?? ""
        return stored.isEmpty ? Self.defaultModelID : stored
    }

    /// Mirrors mlx's `load_default_library` lookup (device.cpp): colocated mlx.metallib next
    /// to the executable, then the SwiftPM resource bundle. SwiftPM CLI builds cannot compile
    /// Metal shaders, so without one of these the first MLX call would abort the process —
    /// better to refuse cleanly here.
    nonisolated static var metalRuntimeAvailable: Bool {
        let fm = FileManager.default
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            for rel in ["mlx.metallib", "Resources/mlx.metallib", "Resources/default.metallib"]
            where fm.fileExists(atPath: dir.appendingPathComponent(rel).path) { return true }
        }
        for bundle in Bundle.allFrameworks + Bundle.allBundles
        where bundle.bundleIdentifier == "mlx-swift_Cmlx" {
            if bundle.url(forResource: "default", withExtension: "metallib") != nil { return true }
        }
        return false
    }

    /// Loads (or reuses) the model container for the currently selected repo. Switching the
    /// model in Settings drops the old container on the next call.
    private func ensureContainer() async throws -> ModelContainer {
        guard Self.metalRuntimeAvailable else {
            Logger.infra.error("MLX backend selected but no Metal library is bundled (SwiftPM build?)")
            throw CorrectionError.serverNotRunning
        }
        let modelID = selectedModelID
        if let container, loadedModelID == modelID { return container }
        container = nil  // free the previous model's GPU buffers before loading the next
        Logger.infra.info("MLX: loading \(modelID, privacy: .public)")
        let loaded = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: modelID))
        container = loaded
        loadedModelID = modelID
        return loaded
    }

    /// Fresh single-turn session per request: PromptEngine builds the full prompt, so no
    /// chat history or system instructions are wanted across calls.
    private func makeSession() async throws -> ChatSession {
        let container = try await ensureContainer()
        return ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.3))
    }

    private func generate(_ prompt: String) async throws -> String {
        try await makeSession().respond(to: prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - LLMService

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 500, 502: throw CorrectionError.serverTimeout
        case 503: throw CorrectionError.serverNotRunning
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func correct(text: String, promptType: PromptType, language: String) async throws -> CorrectionResult {
        let lang = language.isEmpty
            ? LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
            : language
        let engine = PromptEngine(language: lang, style: await resolveStyle())
        let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

        let corrected = try await generate(prompt)
        let validated = validateCorrection(original: text, corrected: corrected, isFluency: promptType.isFluency)

        return CorrectionResult(
            original: text, corrected: validated,
            modelID: selectedModelID, confidence: Constants.defaultConfidence, promptType: promptType.label
        )
    }

    func correctFluency(text: String) async throws -> CorrectionResult {
        try await correct(text: text, promptType: .fluency, language: "")
    }

    func explain(original: String, corrected: String) async throws -> String {
        let lang = LanguageDetector.detect(text: corrected, fallbackLanguage: resolvedLanguage)
        let engine = PromptEngine(language: lang)
        let prompt = engine.buildExplainPrompt(original: original, corrected: corrected, customInstruction: nil)
        return try await generate(prompt)
    }

    func streamCorrect(text: String, promptType: PromptType) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lang = LanguageDetector.detect(text: text, fallbackLanguage: resolvedLanguage)
                    let engine = PromptEngine(language: lang, style: await resolveStyle())
                    let prompt = engine.buildPrompt(for: text, type: promptType, customInstruction: nil)

                    // Yield the accumulated text (not deltas) — same contract as the other
                    // services' streamCorrect implementations.
                    let session = try await self.makeSession()
                    var accumulated = ""
                    for try await chunk in session.streamResponse(to: prompt) {
                        guard !Task.isCancelled else { return }
                        accumulated += chunk
                        let snapshot = accumulated
                        let yield: @Sendable () -> Void = { continuation.yield(snapshot) }
                        await MainActor.run { yield() }
                    }
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
