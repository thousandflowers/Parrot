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
    /// One URLSession per file being downloaded (cancelled together by cancelActiveDownload).
    private var activeDownloadSessions: [String: URLSession] = [:]
    /// In-flight downloads by filename: a second request for the same file joins the first
    /// instead of appending to the same `.partial`.
    private var inFlightDownloads: [String: Task<URL, Error>] = [:]

    private let modelsDir: URL = {
        guard let appSupport = AppPaths.applicationSupport else {
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
        activeDownloadSessions.values.forEach { $0.invalidateAndCancel() }
        activeDownloadSessions = [:]
        inFlightDownloads.values.forEach { $0.cancel() }
        inFlightDownloads = [:]
    }

    nonisolated var modelsDirPath: String {
        let appSupport = AppPaths.applicationSupport
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
            let external = adoptedModelPaths().first { Self.adoptedPath($0, matchesModelID: id) }
            if let ext = external, FileManager.default.fileExists(atPath: ext) {
                return ext
            }
        }
        // Selected model missing (or none selected): use an installed one. Sorted so the choice
        // is stable across launches (directory order is not), and logged because it differs from
        // what Settings shows.
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)),
              let firstModel = contents.filter({ $0.hasSuffix(".gguf") }).sorted().first else {
            Logger.infra.debug("ModelManager: no .gguf models found in \(self.modelsDir.path(percentEncoded: false))")
            return nil
        }
        if !cleanID.isEmpty {
            Logger.infra.warning("ModelManager: selected model \(cleanID, privacy: .public) not installed — using \(firstModel, privacy: .public)")
        }
        return modelsDir.appendingPathComponent(firstModel).path(percentEncoded: false)
    }

    nonisolated func adoptedModelPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.externalModelPaths) ?? []
    }

    /// Removes a downloaded model by ID. Deletes the file from the models directory and
    /// un-adopts exactly-matching adopted paths. Adopted files outside the app's models dir
    /// (LM Studio, Ollama, user folders) are never deleted — only forgotten.
    /// - Parameter id: The model ID (with or without .gguf extension).
    func removeModel(id: String) {
        let cleanID = id.hasSuffix(".gguf") ? String(id.dropLast(5)) : id
        let dirPath = modelsDir.path(percentEncoded: false)

        if let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) {
            let target = "\(cleanID.lowercased()).gguf"
            if let match = files.first(where: { $0.hasSuffix(".gguf") && $0.lowercased() == target }) {
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent(match))
                Logger.infra.debug("ModelManager: deleted model file \(match)")
            }
        }

        let adopted = adoptedModelPaths()
        let toRemove = adopted.filter { Self.adoptedPath($0, matchesModelID: id) }
        UserDefaults.standard.set(adopted.filter { !toRemove.contains($0) }, forKey: Constants.UserDefaultsKey.externalModelPaths)
        toRemove.forEach(deleteIfInsideModelsDir)

        invalidateCache()
    }

    /// Removes a discovered local model by its path.
    /// - Parameter model: The DiscoveredModel to delete.
    func removeLocalModel(_ model: DiscoveredModel) {
        if Self.isPath(model.path, inside: modelsDir.path(percentEncoded: false)) {
            removeModel(id: model.id)
            return
        }
        // External file: un-adopt only. It belongs to the user / another app.
        let adopted = adoptedModelPaths()
        UserDefaults.standard.set(adopted.filter { $0 != model.path }, forKey: Constants.UserDefaultsKey.externalModelPaths)
        Logger.infra.info("ModelManager: un-adopted external model (file kept) at \(model.path, privacy: .public)")
        invalidateCache()
    }

    private func deleteIfInsideModelsDir(_ path: String) {
        guard Self.isPath(path, inside: modelsDir.path(percentEncoded: false)) else {
            Logger.infra.info("ModelManager: un-adopted external model (file kept) at \(path, privacy: .public)")
            return
        }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            Logger.infra.error("ModelManager: failed to delete \(path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Exact match of an adopted path against a model id: same filename (case-insensitive,
    /// `.gguf` optional) or the full path itself (discovered models use the path as id).
    static func adoptedPath(_ path: String, matchesModelID id: String) -> Bool {
        let cleanID = id.lowercased().hasSuffix(".gguf") ? String(id.dropLast(5)) : id
        guard !cleanID.isEmpty else { return false }
        let lowerPath = path.lowercased()
        let filename = (lowerPath as NSString).lastPathComponent
        let lowerID = cleanID.lowercased()
        return filename == "\(lowerID).gguf" || lowerPath == lowerID || lowerPath == "\(lowerID).gguf"
    }

    /// True when `path` (after resolving `..`) lies inside directory `dir`.
    static func isPath(_ path: String, inside dir: String) -> Bool {
        let file = URL(fileURLWithPath: path).standardizedFileURL.path
        let base = URL(fileURLWithPath: dir).standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return file.hasPrefix(prefix)
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
        invalidateCache()
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
            do {
                try KeychainService.shared.save(key: legacy, for: "hftoken")
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.hfToken)
            } catch {
                // Keep the legacy copy: deleting it now would lose the token.
                Logger.infra.error("ModelManager: HF token migration to Keychain failed — \(error.localizedDescription, privacy: .public)")
            }
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
        } catch let error as ModelDownloadError {
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

    /// Downloads `url` into the models dir, resuming a `.partial` with a Range request.
    /// `allowResume: false` discards any partial and starts over (used after a 416 or a
    /// Content-Range that does not continue the partial).
    private func downloadWithResume(from url: URL, progressHandler: ((Double) -> Void)?, token: String?,
                                    allowResume: Bool = true) async throws -> URL {
        let filename = url.lastPathComponent
        let destURL = modelsDir.appendingPathComponent(filename)
        let partialURL = modelsDir.appendingPathComponent("\(filename).partial")
        if !allowResume { removePartial(partialURL) }
        let existingSize = Self.fileSize(atPath: partialURL.path(percentEncoded: false))

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
        activeDownloadSessions[filename] = session
        defer {
            if activeDownloadSessions[filename] === session { activeDownloadSessions[filename] = nil }
            session.invalidateAndCancel()
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let decision = Self.resumeDecision(
            statusCode: httpResponse.statusCode, existingSize: existingSize,
            contentRange: httpResponse.value(forHTTPHeaderField: "Content-Range"),
            expectedContentLength: httpResponse.expectedContentLength)

        let totalExpected: Int64
        let startOffset: Int64
        switch decision {
        case .alreadyComplete:
            Logger.infra.info("ModelManager: \(filename, privacy: .public).partial is already complete (HTTP 416)")
            return try finalizePartial(partialURL, to: destURL, expectedTotal: existingSize)
        case .restartWithoutRange:
            guard allowResume else {
                Logger.infra.error("Model download: unusable response (HTTP \(httpResponse.statusCode, privacy: .public)) even without Range")
                throw URLError(.badServerResponse)
            }
            Logger.infra.info("ModelManager: partial for \(filename, privacy: .public) not resumable (HTTP \(httpResponse.statusCode, privacy: .public)) — restarting")
            return try await downloadWithResume(from: url, progressHandler: progressHandler, token: token, allowResume: false)
        case .fail:
            throw downloadFailure(statusCode: httpResponse.statusCode, url: url)
        case .fresh(let total):
            removePartial(partialURL)
            totalExpected = total
            startOffset = 0
        case .append(let total):
            totalExpected = total
            startOffset = existingSize
        }

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        try ensureFreeSpace(needed: totalExpected > 0 ? totalExpected - startOffset : 0)

        let partialPath = partialURL.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: partialPath) {
            FileManager.default.createFile(atPath: partialPath, contents: nil)
        }
        guard let fileHandle = FileHandle(forWritingAtPath: partialPath) else {
            throw URLError(.cannotCreateFile)
        }
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()

        try await writeChunked(from: asyncBytes, to: fileHandle,
                               startOffset: startOffset, totalExpected: totalExpected,
                               progressHandler: progressHandler)
        try fileHandle.synchronize()
        progressHandler?(1.0)

        return try finalizePartial(partialURL, to: destURL, expectedTotal: totalExpected)
    }

    /// Moves a finished `.partial` into place after checking its size against the expected total.
    private func finalizePartial(_ partialURL: URL, to destURL: URL, expectedTotal: Int64) throws -> URL {
        let actual = Self.fileSize(atPath: partialURL.path(percentEncoded: false))
        if expectedTotal > 0, actual != expectedTotal {
            Logger.infra.error("ModelManager: \(partialURL.lastPathComponent, privacy: .public) is \(actual, privacy: .public) bytes, expected \(expectedTotal, privacy: .public)")
            guard actual < expectedTotal else {
                removePartial(partialURL)
                throw ModelDownloadError.sizeMismatch(expected: expectedTotal, actual: actual)
            }
            // Connection ended early: keep the partial so the next attempt resumes it.
            throw URLError(.networkConnectionLost)
        }
        let destPath = destURL.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: destPath) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: partialURL, to: destURL)
        Logger.infra.debug("ModelManager: downloaded model to \(destPath)")
        return destURL
    }

    private func downloadFailure(statusCode: Int, url: URL) -> Error {
        switch statusCode {
        case 401, 403:
            Logger.infra.error("Model download: auth required (HTTP \(statusCode, privacy: .public)). Set HF token in Settings > Advanced.")
            return CorrectionError.modelDownloadFailed(url: url)
        case 404:
            Logger.infra.error("Model file not found (HTTP 404): \(url.absoluteString, privacy: .public)")
            return CorrectionError.modelDownloadFailed(url: url)
        default:
            Logger.infra.error("Model download failed: HTTP \(statusCode, privacy: .public) for \(url.absoluteString, privacy: .public)")
            return URLError(.badServerResponse)
        }
    }

    private func ensureFreeSpace(needed: Int64) throws {
        let values = try? modelsDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values?.volumeAvailableCapacityForImportantUsage
        guard Self.hasEnoughSpace(available: available, needed: needed, margin: Constants.downloadFreeSpaceMarginBytes) else {
            throw ModelDownloadError.insufficientDiskSpace(needed: needed + Constants.downloadFreeSpaceMarginBytes,
                                                           available: available ?? 0)
        }
    }

    private func removePartial(_ partialURL: URL) {
        guard FileManager.default.fileExists(atPath: partialURL.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: partialURL)
        } catch {
            Logger.infra.error("ModelManager: failed to remove partial file — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Resume logic (pure, testable)

    struct ContentRange: Equatable {
        let start: Int64?   // nil for "bytes */total"
        let total: Int64?   // nil for ".../*"
    }

    enum DownloadResumeDecision: Equatable {
        case fresh(total: Int64)       // 200: write from byte 0 (0 = length unknown)
        case append(total: Int64)      // 206 continuing exactly at the partial's end
        case alreadyComplete           // 416 and the partial already has every byte
        case restartWithoutRange       // 416 / 206 that does not continue the partial
        case fail
    }

    static func parseContentRange(_ header: String) -> ContentRange? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let parts = trimmed.dropFirst("bytes ".count).split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let total = Int64(parts[1].trimmingCharacters(in: .whitespaces))
        let range = parts[0].trimmingCharacters(in: .whitespaces)
        if range == "*" { return ContentRange(start: nil, total: total) }
        let bounds = range.split(separator: "-")
        guard bounds.count == 2, let start = Int64(bounds[0]), Int64(bounds[1]) != nil else { return nil }
        return ContentRange(start: start, total: total)
    }

    static func resumeDecision(statusCode: Int, existingSize: Int64, contentRange: String?,
                               expectedContentLength: Int64) -> DownloadResumeDecision {
        let length = max(0, expectedContentLength)
        let range = contentRange.flatMap(parseContentRange)
        switch statusCode {
        case 200:
            return .fresh(total: length)
        case 206:
            guard let range, range.start == existingSize else { return .restartWithoutRange }
            return .append(total: range.total ?? (length > 0 ? existingSize + length : 0))
        case 416:
            guard existingSize > 0, let total = range?.total, total == existingSize else { return .restartWithoutRange }
            return .alreadyComplete
        default:
            return .fail
        }
    }

    /// Unknown capacity or unknown length never blocks a download.
    static func hasEnoughSpace(available: Int64?, needed: Int64, margin: Int64) -> Bool {
        guard needed > 0, let available else { return true }
        return available >= needed + margin
    }

    private static func fileSize(atPath path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64, size > 0 else { return 0 }
        return size
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
        let key = url.lastPathComponent
        if let existing = inFlightDownloads[key] {
            Logger.infra.info("ModelManager: joining in-flight download of \(key, privacy: .public)")
            return try await existing.value
        }
        let task = Task {
            try await self.performDownload(from: url, expectedSHA256: expectedSHA256,
                                           progressHandler: progressHandler, verificationHandler: verificationHandler)
        }
        inFlightDownloads[key] = task
        defer { if inFlightDownloads[key] == task { inFlightDownloads[key] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performDownload(from url: URL, expectedSHA256: String?, progressHandler: ((Double) -> Void)?,
                                 verificationHandler: ((Double) -> Void)?) async throws -> URL {
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

        removePartial(modelsDir.appendingPathComponent("\(destURL.lastPathComponent).partial"))
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

enum ModelDownloadError: LocalizedError, Equatable {
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case sizeMismatch(expected: Int64, actual: Int64)

    var errorDescription: String? {
        let fmt = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        switch self {
        case .insufficientDiskSpace(let needed, let available):
            return "Not enough disk space for this model: needs \(fmt(needed)), \(fmt(available)) free. Free up space and try again."
        case .sizeMismatch(let expected, let actual):
            return "The downloaded model has the wrong size (\(fmt(actual)) instead of \(fmt(expected))). Please download it again."
        }
    }
}

enum DownloadProgress: Sendable {
    case downloading(Double)
    case verifying(Double)
    case complete
}
