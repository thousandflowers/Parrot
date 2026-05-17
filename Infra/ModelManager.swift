import Foundation
import CryptoKit
import os

struct ModelRecommendation: Sendable {
    let id: String
    let name: String
    let reason: String
    let sizeLabel: String
    let ramRequired: Int
    let url: URL
    let expectedSHA256: String?
    var warning: String?
    let isOnboardingCandidate: Bool

    init(
        id: String,
        name: String,
        reason: String,
        sizeLabel: String = "",
        ramRequired: Int,
        url: URL,
        expectedSHA256: String?,
        warning: String? = nil,
        isOnboardingCandidate: Bool = true
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.sizeLabel = sizeLabel
        self.ramRequired = ramRequired
        self.url = url
        self.expectedSHA256 = expectedSHA256
        self.warning = warning
        self.isOnboardingCandidate = isOnboardingCandidate
    }
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
        // Heal stale selectedModelID so the UI reflects what's actually on disk.
        let fallbackID = String(firstModel.dropLast(5))
        UserDefaults.standard.set(fallbackID, forKey: Constants.UserDefaultsKey.selectedModelID)
        return modelsDir.appendingPathComponent(firstModel).path(percentEncoded: false)
    }

    func recommendedDefaultModel() -> ModelRecommendation? {
        let lang = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        var rec = ModelCatalog.recommended(ramGB: getSystemRAM(), language: lang)
        if getSystemRAM() < 12 && rec.id == "gemma-4-E2B-it-q4_k_m" {
            rec.warning = "Questo modello richiede ~3.5 GB RAM. Chiudi altre app per migliori prestazioni."
        }
        return rec
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
            os_log(.debug, "ModelManager: retrying with hf-mirror.com")
            do {
                return try await downloadWithProgress(from: mirror, progressHandler: progressHandler)
            } catch {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
        }
    }

    private func downloadWithProgress(from url: URL, progressHandler: ((Double) -> Void)?) async throws -> URL {
        final class Box: @unchecked Sendable {
            var obs: NSKeyValueObservation?
            var task: URLSessionDownloadTask?
            func cancel() { obs?.invalidate(); obs = nil; task?.cancel() }
        }
        let box = Box()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                    box.obs?.invalidate()
                    box.obs = nil
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode),
                          let tempURL else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    let destURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try? FileManager.default.removeItem(at: destURL)
                    }
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destURL)
                        continuation.resume(returning: destURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.task = task
                box.obs = task.progress.observe(\.fractionCompleted, options: .new) { progress, _ in
                    let total = progress.totalUnitCount
                    let completed = progress.completedUnitCount
                    if total > 0 {
                        progressHandler?(progress.fractionCompleted)
                    } else if completed > 0 {
                        progressHandler?(-Double(completed))
                    }
                }
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    func downloadModel(from url: URL, expectedSHA256: String? = nil, progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let filename = url.lastPathComponent
        // Clean up any leftover partial files from old download sessions
        let partialPath = modelsDir.appendingPathComponent(filename + ".partial")
        try? FileManager.default.removeItem(at: partialPath)

        let tempURL = try await downloadFile(from: url, progressHandler: progressHandler)
        defer { try? FileManager.default.removeItem(at: tempURL) }

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
        guard fileSize > 10_000_000 else {
            // Small file: likely an HTML auth/error page, not a model
            let isHTML = isHTMLFile(at: destination)
            try? FileManager.default.removeItem(at: destination)
            throw isHTML
                ? CorrectionError.modelDownloadFailed(url: url)
                : CorrectionError.modelCorrupted(expectedSHA: "file-too-small")
        }
        guard GGUFVersionCheck.isCompatible(filePath: destination.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: destination)
            throw CorrectionError.modelCorrupted(expectedSHA: "not-gguf")
        }

        if let expected = expectedSHA256 {
            guard verifySHA256(filePath: destination.path(percentEncoded: false), expectedSHA: expected) else {
                try? FileManager.default.removeItem(at: destination)
                throw CorrectionError.modelCorrupted(expectedSHA: String(expected.prefix(12)))
            }
        }

        return destination
    }

    private func isHTMLFile(at url: URL) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path(percentEncoded: false)),
              let data = try? handle.read(upToCount: 512) else { return false }
        defer { try? handle.close() }
        let prefix = (String(data: data, encoding: .utf8) ?? "").lowercased()
        return prefix.contains("<!doctype") || prefix.contains("<html")
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



    // MARK: - llama-server binary

    /// Canonical path where the app stores its own llama-server copy.
    nonisolated var llamaServerDestination: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RefineClone/llama-server")
    }

    /// Returns the URL of a usable llama-server binary, checking several locations.
    nonisolated func resolvedLlamaServerURL() -> URL? {
        var candidates: [String] = [
            Bundle.main.bundlePath + "/Contents/MacOS/llama-server",
            llamaServerDestination.path(percentEncoded: false),
            "/opt/homebrew/bin/llama-server",
            "/opt/homebrew/opt/llama.cpp/bin/llama-server",
            "/usr/local/bin/llama-server",
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":").map(String.init) {
                candidates.append(dir + "/llama-server")
            }
        }
        return candidates
            .first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Returns the path to Homebrew's brew binary, or nil if not installed.
    nonisolated func resolvedBrewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    func downloadLlamaServerWithProgress() -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let brew = resolvedBrewPath() else {
                        throw CorrectionError.serverNotRunning   // brew not found
                    }

                    // Run: brew install llama.cpp
                    // terminationHandler fires on a background queue
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        continuation.yield(0.1)
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: brew)
                        process.arguments = ["install", "llama.cpp"]
                        process.standardOutput = Pipe()
                        process.standardError = Pipe()
                        process.terminationHandler = { p in
                            if p.terminationStatus == 0 {
                                cont.resume()
                            } else {
                                cont.resume(throwing: CorrectionError.serverNotRunning)
                            }
                        }
                        do { try process.run() } catch { cont.resume(throwing: error) }
                    }

                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    guard !Task.isCancelled else { return }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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

