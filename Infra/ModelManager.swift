import Foundation
import CryptoKit
import os

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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            os_log(.error, "Cannot locate Application Support directory")
            return FileManager.default.temporaryDirectory.appendingPathComponent("RefineClone/Models")
        }
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

    func recommendedDefaultModel() -> ModelRecommendation? {
        let lang = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        let ramGB = getSystemRAM()

        func makeRec(id: String, name: String, reason: String, ramRequired: Int, urlString: String) -> ModelRecommendation? {
            guard let url = URL(string: urlString) else {
                os_log(.error, "Invalid model URL: %{public}@", urlString)
                return nil
            }
            return ModelRecommendation(
                id: id, name: name, reason: reason, ramRequired: ramRequired, url: url, expectedSHA256: nil
            )
        }

        if ["zh", "zh-Hans", "zh-Hant", "zh-HK"].contains(lang) {
            return makeRec(
                id: "qwen2.5-1.5b-instruct-q4_k_m",
                name: "Qwen 2.5 1.5B Instruct",
                reason: "Ottimizzato per lingua cinese",
                ramRequired: 2,
                urlString: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
            )
        } else {
            if ramGB >= 16 {
                return makeRec(
                    id: "gemma-4-E4B-it-q4_k_m",
                    name: "Gemma 4 E4B IT (8B)",
                    reason: "Massima qualita per lingue occidentali (Mac 16GB+)",
                    ramRequired: 6,
                    urlString: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf"
                )
            } else {
                guard let rec = makeRec(
                    id: "gemma-4-E2B-it-q4_k_m",
                    name: "Gemma 4 E2B IT (5B)",
                    reason: "Ottimizzato per lingue occidentali",
                    ramRequired: 4,
                    urlString: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
                ) else { return nil }
                var mutableRec = rec
                if ramGB < 12 {
                    mutableRec.warning = "Questo modello richiede ~3.5GB RAM. Chiudi altre app per migliori prestazioni."
                }
                return mutableRec
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
            os_log(.info, "Trying mirror: hf-mirror.com")
            do {
                return try await downloadWithProgress(from: mirror, progressHandler: progressHandler)
            } catch {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
        }
    }

    private func downloadWithProgress(from url: URL, progressHandler: ((Double) -> Void)?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = ProgressDelegate(progressHandler: progressHandler) {
                continuation.resume(with: $0)
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func downloadModel(from url: URL, expectedSHA256: String? = nil, progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let tempURL = try await downloadFile(from: url, progressHandler: progressHandler)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let filename = url.lastPathComponent
        let destination = modelsDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        guard FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: destination)
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }
        let fileSize: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))
            fileSize = (attrs[.size] as? Int) ?? 0
        } catch {
            os_log(.error, "ModelManager: cannot read file attributes: %{public}@", error.localizedDescription)
            try? FileManager.default.removeItem(at: destination)
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }
        guard fileSize > 10_000_000,
              GGUFVersionCheck.isCompatible(filePath: destination.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: destination)
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }

        if let expected = expectedSHA256 {
            guard verifySHA256(filePath: destination.path(percentEncoded: false), expectedSHA: expected) else {
                try? FileManager.default.removeItem(at: destination)
                throw CorrectionError.modelCorrupted(expectedSHA: String(expected.prefix(12)))
            }
        }

        return destination
    }

    private func verifySHA256(filePath: String, expectedSHA: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return false
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576) {
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let computedHex = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        return computedHex.lowercased() == expectedSHA.lowercased()
    }



    func downloadModelWithProgress(from url: URL, expectedSHA256: String? = nil) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await downloadModel(
                        from: url,
                        expectedSHA256: expectedSHA256,
                        progressHandler: { fraction in
                            continuation.yield(fraction)
                        }
                    )
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
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
    let completion: (Result<URL, Error>) -> Void
    private var downloadLocation: URL?
    private var responseError: Error?

    init(progressHandler: ((Double) -> Void)?, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progressHandler = progressHandler
        self.completion = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let handler = progressHandler else { return }
        handler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(location.lastPathComponent)
        if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: destURL)
        }
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            downloadLocation = destURL
        } catch {
            responseError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.invalidateAndCancel()
        if let error = error {
            completion(.failure(error))
            return
        }
        if let responseError = responseError {
            completion(.failure(responseError))
            return
        }
        guard let url = downloadLocation else {
            completion(.failure(URLError(.cannotMoveFile)))
            return
        }
        guard let httpResponse = task.response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            completion(.failure(URLError(.badServerResponse)))
            return
        }
        completion(.success(url))
    }
}
