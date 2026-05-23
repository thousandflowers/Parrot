import Foundation
import CryptoKit
import OSLog

struct ModelRecommendation: Sendable {
    let id: String
    let name: String
    let reason: String
    var sizeLabel: String?
    let ramRequired: Int
    let url: URL
    let expectedSHA256: String?
    var warning: String?
    var isOnboardingCandidate: Bool = false
}

struct DiscoveredModel: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let source: String
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

    private var _cachedModelPath: String?
    private var _lastCacheTime: Date = .distantPast
    private var _activeDownloadSession: URLSession?

    private let modelsDir: URL = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.infra.error("Cannot locate Application Support directory")
            return FileManager.default.temporaryDirectory.appendingPathComponent("Parrot/Models")
        }
        return appSupport.appendingPathComponent("Parrot/Models")
    }()

    private static let scanDirs: [String] = [
        "~/Library/Application Support/nomic.ai/GPT4All",
        "~/.cache/lm-studio/models",
        "~/.cache/lmstudio/models",
        "~/LM Studio/models",
        "~/models",
        "~/.ollama/models",
    ]

    nonisolated var currentModelPath: String? {
        resolveCurrentModelPath()
    }

    func getCurrentModelPath() async -> String? {
        // Cache for 30 seconds or until invalidated
        if let cached = _cachedModelPath, Date().timeIntervalSince(_lastCacheTime) < 30 {
            return cached
        }
        
        let path = resolveCurrentModelPath()
        _cachedModelPath = path
        _lastCacheTime = Date()
        return path
    }
    
    func invalidateCache() {
        _cachedModelPath = nil
        _lastCacheTime = .distantPast
    }

    func cancelActiveDownload() {
        _activeDownloadSession?.invalidateAndCancel()
        _activeDownloadSession = nil
    }

    nonisolated var modelsDirPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Parrot/Models").path(percentEncoded: false)
    }

    private nonisolated func resolveCurrentModelPath() -> String? {
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? ""
        let cleanID = id.hasSuffix(".gguf") ? String(id.dropLast(5)) : id
        if !cleanID.isEmpty {
            let dirPath = modelsDir.path(percentEncoded: false)
            // Case-insensitive scan of own models dir
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
                let target = "\(cleanID.lowercased()).gguf"
                if let match = files.first(where: { $0.hasSuffix(".gguf") && $0.lowercased() == target }) {
                    return modelsDir.appendingPathComponent(match).path(percentEncoded: false)
                }
            }
            // Case-insensitive check of external/adopted paths
            let external = adoptedModelPaths().first {
                let filename = ($0 as NSString).lastPathComponent
                return filename.lowercased() == "\(cleanID.lowercased()).gguf" || $0.lowercased().contains(cleanID.lowercased())
            }
            if let ext = external, FileManager.default.fileExists(atPath: ext) {
                return ext
            }
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)),
              let firstModel = contents.first(where: { $0.hasSuffix(".gguf") }) else {
            Logger.infra.debug("ModelManager: no .gguf models found in \(self.modelsDir.path(percentEncoded: false))")
            return nil
        }
        return modelsDir.appendingPathComponent(firstModel).path(percentEncoded: false)
    }

    nonisolated func adoptedModelPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.externalModelPaths) ?? []
    }

    func adoptModel(path: String) {
        var paths = adoptedModelPaths()
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: Constants.UserDefaultsKey.externalModelPaths)
        let name = (path as NSString).lastPathComponent
        let modelID = name.hasSuffix(".gguf") ? String(name.dropLast(5)) : name
        if UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)?.isEmpty != false {
            UserDefaults.standard.set(modelID, forKey: Constants.UserDefaultsKey.selectedModelID)
        }
    }

    func discoverExternalModels() -> [DiscoveredModel] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var results: [DiscoveredModel] = []
        var seen = Set<String>()

        for dir in Self.scanDirs {
            let expanded = dir.replacingOccurrences(of: "~", with: home)
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: expanded) else { continue }
            for file in files where file.hasSuffix(".gguf") {
                let fullPath = (expanded as NSString).appendingPathComponent(file)
                let resolved = (fullPath as NSString).resolvingSymlinksInPath
                guard !seen.contains(resolved) else { continue }
                seen.insert(resolved)
                guard GGUFVersionCheck.isCompatible(filePath: resolved) else { continue }
                let attrs = (try? FileManager.default.attributesOfItem(atPath: resolved))
                let size = (attrs?[.size] as? Int64) ?? 0
                let source = dir.contains("LM Studio") || dir.contains("lm-studio") ? "LM Studio"
                    : dir.contains("GPT4All") ? "GPT4All"
                    : dir.contains("ollama") ? "Ollama"
                    : dir.contains("Downloads") ? "Downloads"
                    : dir.contains("Documents") ? "Documents"
                    : "Found"
                results.append(DiscoveredModel(
                    id: resolved,
                    name: file.replacingOccurrences(of: ".gguf", with: ""),
                    path: resolved,
                    size: size,
                    source: source
                ))
            }
        }
        return results.sorted { $0.size > $1.size }
    }

    func localModels() -> [DiscoveredModel] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)) else { return [] }
        return files
            .filter { $0.hasSuffix(".gguf") }
            .compactMap { filename in
                let path = modelsDir.appendingPathComponent(filename).path(percentEncoded: false)
                guard GGUFVersionCheck.isCompatible(filePath: path) else { return nil }
                let attrs = (try? FileManager.default.attributesOfItem(atPath: path))
                let size = (attrs?[.size] as? Int64) ?? 0
                return DiscoveredModel(
                    id: String(filename.dropLast(5)),
                    name: String(filename.dropLast(5)),
                    path: path,
                    size: size,
                    source: "Local"
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func recommendedModels() -> [ModelRecommendation] {
        let ramGB = getSystemRAM()
        return ModelCatalog.all.map { model in
            var m = model
            m.warning = ramGB > 0 && ramGB < model.ramRequired
                ? "Requires ~\(model.ramRequired)GB RAM (you have \(ramGB)GB). May use swap."
                : nil
            return m
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

    private func hfToken() -> String? {
        if let token = try? KeychainService.shared.load(for: "hftoken"), !token.isEmpty {
            return token
        }
        // Migrate legacy UserDefaults token to Keychain on first read
        if let legacy = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.hfToken), !legacy.isEmpty {
            try? KeychainService.shared.save(key: legacy, for: "hftoken")
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.hfToken)
            return legacy
        }
        return nil
    }

    private func downloadSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = Constants.downloadTimeout
        config.timeoutIntervalForRequest = 20  // detect stalls after 20s, not 60s
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }

    private func downloadFile(from url: URL, progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        let token = hfToken()
        do {
            return try await downloadWithResume(from: url, progressHandler: progressHandler, token: token)
        } catch let error as CorrectionError {
            throw error
        } catch {
            guard let mirror = mirrorURL(for: url) else {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
            Logger.infra.info("Primary failed (\(error.localizedDescription, privacy: .public)), trying mirror: hf-mirror.com")
            do {
                return try await downloadWithResume(from: mirror, progressHandler: progressHandler, token: token)
            } catch {
                throw CorrectionError.modelDownloadFailed(url: url)
            }
        }
    }

    private func downloadWithResume(from url: URL, progressHandler: ((Double) -> Void)?, token: String?) async throws -> URL {
        let filename = url.lastPathComponent
        let destURL = modelsDir.appendingPathComponent(filename)
        let partialURL = modelsDir.appendingPathComponent("\(filename).partial")

        let existingSize: Int64 = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path(percentEncoded: false)),
                  let size = attrs[.size] as? Int64, size > 0 else { return 0 }
            return size
        }()

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("Parrot/1.0", forHTTPHeaderField: "User-Agent")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        let session = downloadSession()
        _activeDownloadSession = session
        defer {
            _activeDownloadSession = nil
            session.invalidateAndCancel()
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
            switch httpResponse.statusCode {
            case 401, 403:
                Logger.infra.error("Model download: auth required (HTTP \(httpResponse.statusCode, privacy: .public)). Set HF token in Settings > Advanced.")
                throw CorrectionError.modelDownloadFailed(url: url)
            case 404:
                Logger.infra.error("Model file not found (HTTP 404): \(url.absoluteString, privacy: .public)")
                throw CorrectionError.modelDownloadFailed(url: url)
            default:
                Logger.infra.error("Model download failed: HTTP \(httpResponse.statusCode, privacy: .public) for \(url.absoluteString, privacy: .public)")
                throw URLError(.badServerResponse)
            }
        }

        let totalExpected: Int64
        let isResume = (httpResponse.statusCode == 206)
        if isResume {
            totalExpected = existingSize + (httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : 0)
        } else {
            totalExpected = httpResponse.expectedContentLength
            if FileManager.default.fileExists(atPath: partialURL.path(percentEncoded: false)) {
                do {
                    try FileManager.default.removeItem(at: partialURL)
                } catch {
                    Logger.infra.error("ModelManager: failed to remove stale partial file — \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let fileHandle: FileHandle
        if let fh = FileHandle(forWritingAtPath: partialURL.path(percentEncoded: false)) {
            fileHandle = fh
            try fileHandle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: partialURL.path(percentEncoded: false), contents: nil)
            guard let fh = FileHandle(forWritingAtPath: partialURL.path(percentEncoded: false)) else {
                throw URLError(.cannotCreateFile)
            }
            fileHandle = fh
        }
        defer { try? fileHandle.close() }

        try await writeChunked(from: asyncBytes, to: fileHandle,
                               startOffset: existingSize, totalExpected: totalExpected,
                               progressHandler: progressHandler)
        progressHandler?(1.0)
        try fileHandle.synchronize()

        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: partialURL, to: destURL)
        Logger.infra.debug("ModelManager: downloaded model to \(destURL.path(percentEncoded: false))")
        return destURL
    }

    private func writeChunked(
        from asyncBytes: URLSession.AsyncBytes,
        to fileHandle: FileHandle,
        startOffset: Int64,
        totalExpected: Int64,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let chunkSize = 65_536
        var buffer = Data(capacity: chunkSize)
        var downloaded = startOffset
        var lastReport: Date = .distantPast

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloaded += 1
            if buffer.count >= chunkSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            if totalExpected > 0, let handler = progressHandler {
                let now = Date()
                if now.timeIntervalSince(lastReport) >= Constants.downloadProgressMinInterval {
                    handler(Double(downloaded) / Double(totalExpected))
                    lastReport = now
                }
            }
        }
        if !buffer.isEmpty { try fileHandle.write(contentsOf: buffer) }
    }

    func downloadModel(from url: URL, expectedSHA256: String? = nil, progressHandler: ((Double) -> Void)? = nil, verificationHandler: ((Double) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destURL = try await downloadFile(from: url, progressHandler: progressHandler)

        guard FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) else {
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }
        let fileSize: Int
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path(percentEncoded: false))
            fileSize = (attrs[.size] as? Int) ?? 0
        } catch {
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }
        guard fileSize > Constants.minModelFileSize,
              GGUFVersionCheck.isCompatible(filePath: destURL.path(percentEncoded: false)) else {
            do { try FileManager.default.removeItem(at: destURL) }
            catch { Logger.infra.error("ModelManager: failed to remove corrupt file — \(error.localizedDescription, privacy: .public)") }
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }

        if let expected = expectedSHA256 {
            let filePath = destURL.path(percentEncoded: false)
            let valid = await Task.detached(priority: .utility) {
                Self.verifySHA256Detached(filePath: filePath, expectedSHA: expected)
            }.value
            guard valid else {
                do { try FileManager.default.removeItem(at: destURL) }
                catch { Logger.infra.error("ModelManager: failed to remove sha256-mismatch file — \(error.localizedDescription, privacy: .public)") }
                throw CorrectionError.modelCorrupted(expectedSHA: String(expected.prefix(12)))
            }
        }

        let partialURL = modelsDir.appendingPathComponent("\(destURL.lastPathComponent).partial")
        do { try FileManager.default.removeItem(at: partialURL) }
        catch { Logger.infra.error("ModelManager: failed to remove partial file — \(error.localizedDescription, privacy: .public)") }

        return destURL
    }

    private static func verifySHA256Detached(filePath: String, expectedSHA: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: Constants.sha256ChunkSize) {
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let computedHex = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        return computedHex.lowercased() == expectedSHA.lowercased()
    }

    nonisolated func downloadModelWithProgress(from url: URL, expectedSHA256: String? = nil) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await downloadModel(
                        from: url,
                        expectedSHA256: expectedSHA256,
                        progressHandler: { fraction in
                            continuation.yield(.downloading(fraction))
                        },
                        verificationHandler: { fraction in
                            continuation.yield(.verifying(fraction))
                        }
                    )
                    continuation.yield(.complete)
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

enum DownloadProgress: Sendable {
    case downloading(Double)
    case verifying(Double)
    case complete
}
