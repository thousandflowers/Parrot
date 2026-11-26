import Foundation
import Darwin
import Metal
import OSLog

extension Notification.Name {
    static let serverStateDidChange = Notification.Name("serverStateDidChange")
}

actor ServerManager: Sendable {
    /// Main server for correction/fluency (may reuse an external llama-server on the standard ports).
    static let shared = ServerManager(role: "main")
    /// Dedicated server for inline completion when the user picks a different completion model.
    /// Never reuses an external server (that would serve the wrong model) and uses its own port range.
    static let completion = ServerManager(role: "completion", allowExternalReuse: false, contextSize: 1024)

    /// Stops every llama-server this app launched. Call on quit (AppDelegate) so the
    /// completion server is not left running and holding RAM.
    static func stopAll() async {
        async let main: Void = shared.stop()
        async let completionStop: Void = completion.stop()
        _ = await (main, completionStop)
    }

    private let role: String
    private let allowExternalReuse: Bool
    private let contextSize: Int            // KV context window; smaller = much less RAM
    private var currentModelPath: String?   // model our own process was launched with
    private let pidRecordURL: URL
    private let logURL: URL?
    init(role: String, allowExternalReuse: Bool = true, contextSize: Int = 4096) {
        self.role = role
        self.allowExternalReuse = allowExternalReuse
        self.contextSize = contextSize
        let suffix = role == "main" ? "" : "-\(role)"
        self.pidRecordURL = Self.runDirectory.appendingPathComponent("llama-server\(suffix).pid")
        self.logURL = Self.logsDirectory?.appendingPathComponent("llama-server\(suffix).log")
    }

    private var process: Process?
    private var logHandle: FileHandle?
    private var startupTask: Task<Void, Error>?
    private var forceKillTask: Task<Void, Never>?
    private var reapTask: Task<Void, Never>?
    /// Ports held by a stale server of ours that could not be killed: never adopt them as "external".
    private var excludedPorts: Set<Int> = []
    private var isExternalServer: Bool = false
    private var _currentPort: Int = 0
    var currentPort: Int {
        get { _currentPort }
        set {
            _currentPort = newValue
            NotificationCenter.default.post(name: .serverStateDidChange, object: nil)
        }
    }

    func ensureRunning(modelPath: String) async throws -> Int {
        if let existingTask = startupTask {
            try await existingTask.value
            return currentPort
        }

        // A crash/force-quit leaves our llama-server running; kill it before probing ports,
        // otherwise it would be adopted as an "external" server (wrong model, never stopped).
        if reapTask == nil { reapTask = Task { await reapOrphanOnLaunch() } }
        await reapTask?.value

        // 0. If our own server is already running a DIFFERENT model, restart it so a model change
        //    (user picked a new correction/completion model) actually takes effect.
        if !isExternalServer, currentPort > 0, let cur = currentModelPath, cur != modelPath {
            await stop()
        }

        // 1. Check if current is still healthy
        if currentPort > 0 {
            if await checkServerHealth(port: currentPort) {
                return currentPort
            }
        }

        // 2. Try to find an external server (main server only — the completion server must run
        //    its own model and never adopt whatever is already on the standard ports).
        if allowExternalReuse, let externalPort = await findExistingServer() {
            self.currentPort = externalPort
            self.isExternalServer = true
            return externalPort
        }

        // Re-check after awaits: a concurrent call may have set startupTask in the meantime
        if let existingTask = startupTask {
            try await existingTask.value
            return currentPort
        }

        // 3. Start our own
        let task = Task { try await start(modelPath: modelPath) }
        startupTask = task
        do {
            try await task.value
            startupTask = nil
            return currentPort
        } catch {
            startupTask = nil
            throw error
        }
    }

    private func findExistingServer() async -> Int? {
        // Only probe llama-server ports — NOT 11434 (Ollama), which would cause wrong model to be used
        for port in Constants.candidateServerPorts where !excludedPorts.contains(port) {
            if await checkServerHealth(port: port) {
                return port
            }
        }
        return nil
    }

    private func resolveServerExecutable() -> URL? {
        LlamaInstaller.resolveExecutable().map { URL(fileURLWithPath: $0) }
    }

    func start(modelPath: String) async throws {
        // If process exists but has already exited, clean it up; if still running, return early
        if let existing = process {
            if existing.isRunning { return }
            self.process = nil
            self.currentPort = 0
        }
        self.isExternalServer = false

        guard GGUFVersionCheck.isCompatible(filePath: modelPath) else {
            throw CorrectionError.modelIncompatibleVersion(path: modelPath)
        }

        guard let serverURL = resolveServerExecutable() else {
            throw CorrectionError.serverNotRunning
        }

        try? logHandle?.close()
        logHandle = logURL.flatMap { LogRotation.openAppendHandle(at: $0, maxBytes: Constants.logRotationMaxBytes) }

        // RAM-aware context: KV cache scales with context length. On low-RAM machines (≤8GB)
        // cap it to keep memory in check.
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let effectiveContext = ramGB <= 8 ? min(contextSize, 2048) : contextSize

        for attempt in 0..<3 {
            let (port, probeSock) = try allocatePort()
            currentPort = port

            let process = Process()
            process.executableURL = serverURL
            process.standardOutput = logHandle ?? FileHandle.nullDevice
            process.standardError = logHandle ?? FileHandle.nullDevice
            process.arguments = [
                "-m", modelPath,
                "--host", "127.0.0.1",
                "--port", "\(currentPort)",
                "-c", "\(effectiveContext)",
                "--threads", "\(max(2, ProcessInfo.processInfo.processorCount / 2))",
                "--n-gpu-layers", gpuLayers(),
                "--flash-attn", "auto"
            ]

            close(probeSock)

            do {
                try process.run()
            } catch {
                currentPort = 0
                if attempt < 2 { continue }
                throw CorrectionError.serverNotRunning
            }
            self.process = process
            writePidRecord(process: process, port: port, executable: serverURL)

            do {
                for healthAttempt in 0..<Constants.serverHealthAttempts {
                    if await checkServerHealth(port: currentPort) {
                        self.currentModelPath = modelPath
                        return
                    }
                    guard process.isRunning else { break }
                    let delayMs = min(2000, 250 * Int(pow(2.0, Double(healthAttempt))))
                    try await Task.sleep(for: .milliseconds(delayMs))
                }

                process.terminate()
                self.process = nil
                removePidRecord()
                currentPort = 0
            } catch {
                process.terminate()
                self.process = nil
                removePidRecord()
                currentPort = 0
                throw error
            }
        }

        throw CorrectionError.serverTimeout
    }

    func stop() async {
        startupTask?.cancel()
        startupTask = nil
        currentModelPath = nil

        if isExternalServer {
            self.currentPort = 0
            self.isExternalServer = false
            return
        }
        
        guard let process = process, process.isRunning else {
            self.process = nil
            releaseOwnProcessResources()
            currentPort = 0
            return
        }
        
        let pid = process.processIdentifier
        process.terminate()

        let deadline = Date().addingTimeInterval(Constants.serverStopTimeout)
        while _isProcessRunning(pid) && Date() < deadline {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch is CancellationError {
                break
            } catch {
                break
            }
        }

        if _isProcessRunning(pid) {
            kill(pid_t(pid), SIGKILL)
            // Non-blocking reap: SIGKILL ensures fast exit; avoid blocking the cooperative thread pool.
            waitpid(pid_t(pid), nil, WNOHANG)
        }
        self.process = nil
        releaseOwnProcessResources()
        currentPort = 0
    }

    /// nil when no own process is tracked (external server or not started).
    func ownProcessAlive() -> Bool? {
        guard !isExternalServer, let process else { return nil }
        return process.isRunning
    }

    nonisolated func forceKill() {
        Task { await self.internalForceKill() }
    }

    private func internalForceKill() {
        forceKillTask?.cancel()
        forceKillTask = Task { await stop() }
    }

    private func allocatePort() throws -> (port: Int, socket: Int32) {
        // Try standard fallback first
        if !isPortInUse(11435) {
            if let (p, s) = try? bindTo(port: 11435) { return (p, s) }
        }
        
        // Random port
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw CorrectionError.serverNotRunning }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { close(sock); throw CorrectionError.serverNotRunning }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &len)
            }
        }
        guard getResult == 0 else { close(sock); throw CorrectionError.serverNotRunning }

        let port = Int(UInt16(bigEndian: boundAddr.sin_port))
        return (port, sock)
    }
    
    private func bindTo(port: Int) throws -> (port: Int, socket: Int32) {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw CorrectionError.serverNotRunning }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return (port, sock) }
        close(sock)
        throw CorrectionError.serverNotRunning
    }

    private func isPortInUse(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return true }
        defer { close(sock) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = UInt32(bigEndian: INADDR_LOOPBACK)

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func gpuLayers() -> String {
        guard MTLCreateSystemDefaultDevice() != nil else { return "0" }
        // Subtract 4 GB OS + app overhead from physical to get usable unified memory
        let physGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let usableGB = max(0, physGB - 4)
        if usableGB >= 12 { return "999" }
        if usableGB >= 4  { return "20" }
        return "0"
    }

    private func checkServerHealth(port: Int) async -> Bool {
        guard port > 0 else { return false }
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.0
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func _isProcessRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    private static var logsDirectory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/Parrot")
    }

    // MARK: - Own-process bookkeeping (pid file, log handle)

    private static var runDirectory: URL {
        (AppPaths.applicationSupport
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Parrot/run")
    }

    private func writePidRecord(process: Process, port: Int, executable: URL) {
        let record = ServerPidRecord(pid: process.processIdentifier, port: port,
                                     executablePath: executable.path(percentEncoded: false))
        do {
            try ServerPidRecord.write(record, to: pidRecordURL)
        } catch {
            Logger.server.error("ServerManager[\(self.role, privacy: .public)]: cannot write pid file — \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removePidRecord() {
        ServerPidRecord.remove(at: pidRecordURL)
    }

    private func releaseOwnProcessResources() {
        removePidRecord()
        try? logHandle?.close()
        logHandle = nil
    }

    private func reapOrphanOnLaunch() async {
        let outcome = await Self.reapOrphan(recordURL: pidRecordURL, knownExecutables: LlamaInstaller.candidateExecutables)
        switch outcome {
        case .none:
            break
        case .notOurs:
            Logger.server.info("ServerManager[\(self.role, privacy: .public)]: stale pid file belonged to another program — ignored")
        case .terminated(let pid):
            Logger.server.info("ServerManager[\(self.role, privacy: .public)]: terminated orphaned llama-server pid \(pid, privacy: .public)")
        case .stillRunning(let pid, let port):
            excludedPorts.insert(port)
            Logger.server.error("ServerManager[\(self.role, privacy: .public)]: orphaned llama-server pid \(pid, privacy: .public) survived SIGKILL — port \(port, privacy: .public) will not be adopted")
        }
    }

    // MARK: - Orphan reaping (pure enough to test with a stand-in process)

    enum OrphanReapOutcome: Equatable {
        case none                                  // no pid file, or recorded process is gone
        case notOurs                               // pid reused by an unrelated program
        case terminated(pid: Int32)
        case stillRunning(pid: Int32, port: Int)
    }

    /// Reads the pid file written at spawn; if that pid is alive and runs one of our known
    /// llama-server executables, terminates it (SIGTERM, then SIGKILL). The pid file is removed
    /// unless the process survived.
    static func reapOrphan(recordURL: URL, knownExecutables: [String]) async -> OrphanReapOutcome {
        guard let record = ServerPidRecord.read(from: recordURL) else {
            ServerPidRecord.remove(at: recordURL)
            return .none
        }
        let pid = record.pid
        guard pid > 0, pid != getpid(), isAlive(pid) else {
            ServerPidRecord.remove(at: recordURL)
            return .none
        }
        let known = knownExecutables + [record.executablePath]
        guard isKnownServerExecutable(procPath: processExecutablePath(pid: pid), knownPaths: known) else {
            ServerPidRecord.remove(at: recordURL)
            return .notOurs
        }
        kill(pid, SIGTERM)
        if await waitForExit(pid, timeout: Constants.serverStopTimeout) == false {
            kill(pid, SIGKILL)
            guard await waitForExit(pid, timeout: 1) else {
                return .stillRunning(pid: pid, port: record.port)
            }
        }
        ServerPidRecord.remove(at: recordURL)
        return .terminated(pid: pid)
    }

    static func isKnownServerExecutable(procPath: String?, knownPaths: [String]) -> Bool {
        guard let procPath, !procPath.isEmpty else { return false }
        let resolved = URL(fileURLWithPath: procPath).resolvingSymlinksInPath().path
        return knownPaths.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved }
    }

    /// Executable path of a running process (proc_pidpath), nil if it does not exist.
    static func processExecutablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        // A zombie still answers kill(0) but has no executable path.
        kill(pid, 0) == 0 && processExecutablePath(pid: pid) != nil
    }

    private static func waitForExit(_ pid: Int32, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isAlive(pid) {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }
}

/// What ServerManager writes next to the app's data when it spawns llama-server, so a later
/// launch can recognise (and kill) a server orphaned by a crash or force-quit.
struct ServerPidRecord: Codable, Equatable {
    let pid: Int32
    let port: Int
    let executablePath: String

    static func write(_ record: ServerPidRecord, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> ServerPidRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ServerPidRecord.self, from: data)
    }

    static func remove(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            Logger.server.error("ServerPidRecord: cannot remove \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }
}
