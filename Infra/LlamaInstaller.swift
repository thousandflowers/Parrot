import Foundation

enum LlamaInstallPhase: Equatable {
    case unknown
    case available(path: String)
    case unavailable
    case installing(progress: Double, message: String)  // progress < 0 = indeterminate
    case failed(String)
}

@Observable @MainActor
final class LlamaInstaller {
    static let shared = LlamaInstaller()
    private init() {}

    private(set) var phase: LlamaInstallPhase = .unknown

    // Where we install a self-managed binary (not Homebrew)
    nonisolated static let managedBinURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Parrot/bin/llama-server")
    }()

    // Called by ServerManager and the UI
    nonisolated static func resolveExecutable() -> String? {
        let candidates: [String] = [
            Bundle.main.url(forAuxiliaryExecutable: "llama-server")?.path(percentEncoded: false),
            managedBinURL.path(percentEncoded: false),
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "/usr/bin/llama-server",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func checkAvailability() {
        let path = Self.resolveExecutable()
        phase = path != nil ? .available(path: path!) : .unavailable
    }

    func install() {
        guard !isInstalling else { return }
        Task { await performInstall() }
    }

    func retryAfterFailure() {
        phase = .unavailable
    }

    private var isInstalling: Bool {
        if case .installing = phase { return true }
        return false
    }

    // MARK: - Installation

    private func performInstall() async {
        if let brew = findBrew() {
            await installViaHomebrew(brew)
        } else {
            await installViaGitHub()
        }
    }

    private func findBrew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Homebrew path

    private func installViaHomebrew(_ brew: String) async {
        phase = .installing(progress: -1, message: "Installing via Homebrew (this may take a few minutes)…")

        let exitCode = await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: brew)
            p.arguments = ["install", "llama.cpp"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return Int32(-1) }
            p.waitUntilExit()
            return p.terminationStatus
        }.value

        if exitCode == 0, let path = Self.resolveExecutable() {
            phase = .available(path: path)
        } else {
            // Homebrew failed or llama.cpp formula is not available; try direct download
            await installViaGitHub()
        }
    }

    // MARK: GitHub binary path

    private func installViaGitHub() async {
        phase = .installing(progress: 0, message: "Fetching latest release info…")

        do {
            // 1. Resolve download URL from GitHub API
            let dlURL = try await resolveGitHubAssetURL()

            // 2. Download zip with progress
            phase = .installing(progress: 0.05, message: "Downloading llama-server…")
            let zipFile = try await downloadWithProgress(from: dlURL)
            defer { try? FileManager.default.removeItem(at: zipFile) }

            // 3. Extract
            phase = .installing(progress: 0.82, message: "Extracting…")
            let binary = try await extractLlamaServer(from: zipFile)
            defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }

            // 4. Install
            phase = .installing(progress: 0.96, message: "Installing…")
            try installBinary(from: binary)

            phase = .available(path: Self.managedBinURL.path(percentEncoded: false))

        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func resolveGitHubAssetURL() async throws -> URL {
        guard let apiURL = URL(string: "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest") else {
            throw LlamaInstallerError.invalidURL
        }
        var req = URLRequest(url: apiURL, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw LlamaInstallerError.parseError("Cannot parse GitHub release response")
        }

        let arch = currentArch()
        guard let asset = assets.first(where: {
                  let name = ($0["name"] as? String) ?? ""
                  return name.contains("macos") && name.contains(arch) && name.hasSuffix(".zip")
              }),
              let urlStr = asset["browser_download_url"] as? String,
              let url = URL(string: urlStr) else {
            throw LlamaInstallerError.parseError("No macOS \(arch) binary found in latest release")
        }
        return url
    }

    private func downloadWithProgress(from url: URL) async throws -> URL {
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("llama-dl-\(UUID().uuidString).zip")

        // Use bytes API for progress tracking
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        let totalBytes = (response as? HTTPURLResponse)
            .flatMap { $0.value(forHTTPHeaderField: "Content-Length") }
            .flatMap(Int64.init) ?? 0

        FileManager.default.createFile(atPath: tempZip.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: tempZip)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buf = Data()
        buf.reserveCapacity(65_536)

        for try await byte in asyncBytes {
            buf.append(byte)
            if buf.count >= 65_536 {
                try handle.write(contentsOf: buf)
                received += Int64(buf.count)
                buf.removeAll(keepingCapacity: true)
                if totalBytes > 0 {
                    let fraction = Double(received) / Double(totalBytes)
                    phase = .installing(
                        progress: 0.05 + fraction * 0.75,
                        message: "Downloading… \(Int(fraction * 100))%"
                    )
                }
            }
        }
        if !buf.isEmpty {
            try handle.write(contentsOf: buf)
        }
        try handle.close()

        return tempZip
    }

    private func extractLlamaServer(from zip: URL) async throws -> URL {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("llama-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let extractDirPath = extractDir.path(percentEncoded: false)
        let zipPath = zip.path(percentEncoded: false)

        let exitCode = await Task.detached(priority: .utility) { () -> Int32 in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-q", "-o", zipPath, "*llama-server", "-d", extractDirPath]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return -1 }
            p.waitUntilExit()
            return p.terminationStatus
        }.value

        guard exitCode == 0 else {
            throw LlamaInstallerError.parseError("Extraction failed (unzip exit \(exitCode))")
        }

        guard let binary = findFile(named: "llama-server", in: extractDir) else {
            throw LlamaInstallerError.parseError("llama-server binary not found in the downloaded archive")
        }
        return binary
    }

    private func installBinary(from source: URL) throws {
        let dir = Self.managedBinURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: Self.managedBinURL)
        try FileManager.default.copyItem(at: source, to: Self.managedBinURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755 as NSNumber],
            ofItemAtPath: Self.managedBinURL.path(percentEncoded: false)
        )
    }

    // MARK: - Helpers

    private func findFile(named name: String, in dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles) else { return nil }
        for case let url as URL in e where url.lastPathComponent == name { return url }
        return nil
    }

    private func currentArch() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }.contains("arm") ? "arm64" : "x86_64"
    }
}

private enum LlamaInstallerError: LocalizedError {
    case invalidURL
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid URL"
        case .parseError(let s): return s
        }
    }
}
