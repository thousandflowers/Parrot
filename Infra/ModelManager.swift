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
        let id = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? ""
        let cleanID = id.hasSuffix(".gguf") ? String(id.dropLast(5)) : id
        if !cleanID.isEmpty {
            let ownPath = modelsDir.appendingPathComponent("\(cleanID).gguf").path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: ownPath) {
                return ownPath
            }
            let fullPathID = id.hasSuffix(".gguf") ? id : "\(id).gguf"
            let external = adoptedModelPaths().first { ($0 as NSString).lastPathComponent == fullPathID || $0.contains(cleanID) }
            if let ext = external, FileManager.default.fileExists(atPath: ext) {
                return ext
            }
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)),
              let firstModel = contents.first(where: { $0.hasSuffix(".gguf") }) else {
            return nil
        }
        return modelsDir.appendingPathComponent(firstModel).path(percentEncoded: false)
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
            let ownPath = modelsDir.appendingPathComponent("\(cleanID).gguf").path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: ownPath) {
                return ownPath
            }
            let fullPathID = id.hasSuffix(".gguf") ? id : "\(id).gguf"
            let external = adoptedModelPaths().first { ($0 as NSString).lastPathComponent == fullPathID || $0.contains(cleanID) }
            if let ext = external, FileManager.default.fileExists(atPath: ext) {
                return ext
            }
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)),
              let firstModel = contents.first(where: { $0.hasSuffix(".gguf") }) else {
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

    func recommendedModels() -> [ModelRecommendation] {
        let ramGB = getSystemRAM()

        func rec(id: String, name: String, reason: String, ram: Int, urlString: String, warning: String? = nil) -> ModelRecommendation? {
            guard let url = URL(string: urlString) else { return nil }
            var r = ModelRecommendation(id: id, name: name, reason: reason, ramRequired: ram, url: url, expectedSHA256: nil)
            r.warning = ram > ramGB ? "Requires ~\(ram)GB RAM (you have \(ramGB)GB). May use swap." : warning
            return r
        }

        let all: [ModelRecommendation?] = [
            rec(id: "qwen2.5-0.5b-instruct-q4_k_m",     name: "Qwen 2.5 0.5B",
                reason: "Fastest — ideal for Macs with limited RAM", ram: 1,
                urlString: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"),
            rec(id: "qwen2.5-1.5b-instruct-q4_k_m",    name: "Qwen 2.5 1.5B",
                reason: "Fast, multilingual (great for Italian)", ram: 2,
                urlString: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
            rec(id: "Llama-3.2-1B-Instruct-Q4_K_M",     name: "Llama 3.2 1B",
                reason: "Lightweight, good quality for English", ram: 2,
                urlString: "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"),
            rec(id: "gemma-2-2b-it-Q4_K_M",             name: "Gemma 2 2B IT",
                reason: "Excellent multilingual quality", ram: 3,
                urlString: "https://huggingface.co/lmstudio-community/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf"),
            rec(id: "Llama-3.2-3B-Instruct-Q4_K_M",     name: "Llama 3.2 3B",
                reason: "Good quality/speed balance", ram: 3,
                urlString: "https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"),
            rec(id: "Phi-3.5-mini-instruct-Q4_K_M",     name: "Phi-3.5 Mini",
                reason: "Microsoft — strong grammar reasoning", ram: 4,
                urlString: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"),
            rec(id: "gemma-4-E2B-it-Q4_K_M",            name: "Gemma 4 E2B IT",
                reason: "Latest generation — maximum quality", ram: 4,
                urlString: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"),
        ]
        return all.compactMap { $0 }
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
                try? FileManager.default.removeItem(at: partialURL)
            }
        }

        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        guard let fileHandle = FileHandle(forWritingAtPath: partialURL.path(percentEncoded: false)) else {
            FileManager.default.createFile(atPath: partialURL.path(percentEncoded: false), contents: nil)
            guard let fh = FileHandle(forWritingAtPath: partialURL.path(percentEncoded: false)) else {
                throw URLError(.cannotCreateFile)
            }
            defer { try? fh.close() }
            try await writeChunked(from: asyncBytes, to: fh,
                                   startOffset: existingSize, totalExpected: totalExpected,
                                   progressHandler: progressHandler)
            progressHandler?(1.0)
            try fh.synchronize()
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: partialURL, to: destURL)
            return destURL
        }
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()

        try await writeChunked(from: asyncBytes, to: fileHandle,
                               startOffset: existingSize, totalExpected: totalExpected,
                               progressHandler: progressHandler)
        progressHandler?(1.0)
        try fileHandle.synchronize()

        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: partialURL, to: destURL)
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
            try? FileManager.default.removeItem(at: destURL)
            throw CorrectionError.modelCorrupted(expectedSHA: "file-validation-failed")
        }

        if let expected = expectedSHA256 {
            let valid = verifySHA256(filePath: destURL.path(percentEncoded: false), expectedSHA: expected, progressHandler: verificationHandler)
            guard valid else {
                try? FileManager.default.removeItem(at: destURL)
                throw CorrectionError.modelCorrupted(expectedSHA: String(expected.prefix(12)))
            }
        }

        let partialURL = modelsDir.appendingPathComponent("\(destURL.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: partialURL)

        return destURL
    }

    private func verifySHA256(filePath: String, expectedSHA: String, progressHandler: ((Double) -> Void)? = nil) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        let fileSize: UInt64 = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            return (attrs?[.size] as? UInt64) ?? 0
        }()
        var totalRead: UInt64 = 0
        while let chunk = try? handle.read(upToCount: Constants.sha256ChunkSize) {
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            totalRead += UInt64(chunk.count)
            if fileSize > 0, let handler = progressHandler {
                handler(Double(totalRead) / Double(fileSize))
            }
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
