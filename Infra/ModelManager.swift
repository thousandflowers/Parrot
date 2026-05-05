import Foundation
import CryptoKit


struct ModelRecommendation: Sendable {
    let id: String
    let name: String
    let reason: String
    let ramRequired: Int
    let url: URL
    var warning: String?
}

struct ModelInfo: Codable {
    let id: String
    let name: String
    let url: String
    let size: String
    let ramRequired: Int
    let languages: [String]
    let sha256: String
}

actor ModelManager: Sendable {
    static let shared = ModelManager()

    private let modelsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RefineClone/Models")
    }()

    var currentModelPath: String? {
        let id = PreferencesStore.shared.selectedModelID
        guard !id.isEmpty else { return nil }
        return modelsDir.appendingPathComponent("\(id).gguf").path(percentEncoded: false)
    }

    func recommendedDefaultModel() -> ModelRecommendation {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let ramGB = getSystemRAM()

        if ["zh", "zh-Hans", "zh-Hant", "zh-HK"].contains(lang) {
            return ModelRecommendation(
                id: "qwen2.5-1.5b-instruct-q4_k_m",
                name: "Qwen 2.5 1.5B Instruct",
                reason: "Ottimizzato per lingua cinese",
                ramRequired: 2,
                url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
            )
        } else {
            if ramGB >= 16 {
                return ModelRecommendation(
                    id: "gemma-4-E4B-it-q4_k_m",
                    name: "Gemma 4 E4B IT (8B)",
                    reason: "Massima qualita per lingue occidentali (Mac 16GB+)",
                    ramRequired: 6,
                    url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!
                )
            } else {
                var rec = ModelRecommendation(
                    id: "gemma-4-E2B-it-q4_k_m",
                    name: "Gemma 4 E2B IT (5B)",
                    reason: "Ottimizzato per lingue occidentali",
                    ramRequired: 4,
                    url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!
                )
                if ramGB < 12 {
                    rec.warning = "Questo modello richiede ~3.5GB RAM. Chiudi altre app per migliori prestazioni."
                }
                return rec
            }
        }
    }

    private func getSystemRAM() -> Int {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return Int(bytes / (1024 * 1024 * 1024))
    }



    private func computeSHA256(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func sha256ForFile(_ filename: String) -> String? {
        // Placeholder: in MVP3 this reads from a models.json registry
        // For now, skip verification (returns nil = no check)
        return nil
    }

    func downloadModel(from url: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let filename = url.lastPathComponent
        let destination = modelsDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // SHA-256 integrity check (if sha256 is known for this model)
        if let expectedSHA = sha256ForFile(destination.lastPathComponent) {
            let actualSHA = try computeSHA256(for: destination)
            guard actualSHA == expectedSHA else {
                try FileManager.default.removeItem(at: destination)
                throw CorrectionError.modelCorrupted(expectedSHA: expectedSHA)
            }
        }

        return destination
    }



    func downloadModelWithProgress(from url: URL) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    _ = try await downloadModel(from: url)
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
