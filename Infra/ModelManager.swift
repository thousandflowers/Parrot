import Foundation


struct ModelRecommendation: Sendable {
    let id: String
    let name: String
    let reason: String
    let ramRequired: Int
    let url: URL
    let expectedSHA256: String?
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

    nonisolated var currentModelPath: String? {
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? ""
        let cleanID = id.hasSuffix(".gguf") ? String(id.dropLast(5)) : id
        if !cleanID.isEmpty {
            let path = modelsDir.appendingPathComponent("\(cleanID).gguf").path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)),
              let firstModel = contents.first(where: { $0.hasSuffix(".gguf") }) else {
            return nil
        }
        return modelsDir.appendingPathComponent(firstModel).path(percentEncoded: false)
    }

    func recommendedDefaultModel() -> ModelRecommendation {
        let lang = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        let ramGB = getSystemRAM()

        if ["zh", "zh-Hans", "zh-Hant", "zh-HK"].contains(lang) {
            return ModelRecommendation(
                id: "qwen2.5-1.5b-instruct-q4_k_m",
                name: "Qwen 2.5 1.5B Instruct",
                reason: "Ottimizzato per lingua cinese",
                ramRequired: 2,
                url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
                expectedSHA256: nil
            )
        } else {
            if ramGB >= 16 {
                return ModelRecommendation(
                    id: "gemma-4-E4B-it-q4_k_m",
                    name: "Gemma 4 E4B IT (8B)",
                    reason: "Massima qualita per lingue occidentali (Mac 16GB+)",
                    ramRequired: 6,
                    url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
                    expectedSHA256: nil
                )
            } else {
                var rec = ModelRecommendation(
                    id: "gemma-4-E2B-it-q4_k_m",
                    name: "Gemma 4 E2B IT (5B)",
                    reason: "Ottimizzato per lingue occidentali",
                    ramRequired: 4,
                    url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
                    expectedSHA256: nil
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

    private func mirrorURL(for url: URL) -> URL? {
        guard let host = url.host, host.contains(Constants.huggingFaceHost) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = Constants.huggingFaceMirrorHost
        return components?.url
    }

    private func downloadFile(from url: URL, progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        do {
            return try await downloadWithProgress(from: url, progressHandler: progressHandler)
        } catch {
            guard let mirror = mirrorURL(for: url) else {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
            print("Trying mirror: hf-mirror.com")
            do {
                return try await downloadWithProgress(from: mirror, progressHandler: progressHandler)
            } catch {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
        }
    }

    private func downloadWithProgress(from url: URL, progressHandler: ((Double) -> Void)?) async throws -> URL {
        let delegate = ProgressDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (localURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: localURL, to: destURL)
        return destURL
    }

    func downloadModel(from url: URL, progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let tempURL = try await downloadFile(from: url, progressHandler: progressHandler)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let filename = url.lastPathComponent
        let destination = modelsDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Basic integrity: verify file exists with reasonable size and correct GGUF header
        guard FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)),
              let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false)),
              let fileSize = attrs[.size] as? Int, fileSize > 10_000_000,
              GGUFVersionCheck.isCompatible(filePath: destination.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: destination)
            throw CorrectionError.modelCorrupted(expectedSHA: "invalid-gguf")
        }

        return destination
    }



    func downloadModelWithProgress(from url: URL) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await downloadModel(from: url, progressHandler: { fraction in
                        continuation.yield(fraction)
                    })
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: ((Double) -> Void)?

    init(progressHandler: ((Double) -> Void)?) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let handler = progressHandler else { return }
        handler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
}
