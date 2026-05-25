import Foundation
import Darwin
import Metal

extension Notification.Name {
    static let serverStateDidChange = Notification.Name("serverStateDidChange")
}

actor ServerManager: Sendable {
    static let shared = ServerManager()

    private var process: Process?
    private var startupTask: Task<Void, Error>?
    private var forceKillTask: Task<Void, Never>?
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
        
        // 1. Check if current is still healthy
        if currentPort > 0 {
            if await checkServerHealth(port: currentPort) {
                return currentPort
            }
        }

        // 2. Try to find an external server
        if let externalPort = await findExistingServer() {
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
        for port in Constants.candidateServerPorts {
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

        let logHandle = Self.openServerLogHandle()

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
                "-c", "4096",
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

            do {
                for healthAttempt in 0..<Constants.serverHealthAttempts {
                    if await checkServerHealth(port: currentPort) { return }
                    guard process.isRunning else { break }
                    let delayMs = min(2000, 250 * Int(pow(2.0, Double(healthAttempt))))
                    try await Task.sleep(for: .milliseconds(delayMs))
                }

                process.terminate()
                self.process = nil
                currentPort = 0
            } catch {
                process.terminate()
                self.process = nil
                currentPort = 0
                throw error
            }
        }

        throw CorrectionError.serverTimeout
    }

    func stop() async {
        startupTask?.cancel()
        startupTask = nil

        if isExternalServer {
            self.currentPort = 0
            self.isExternalServer = false
            return
        }
        
        guard let process = process, process.isRunning else {
            self.process = nil
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
        currentPort = 0
    }

    nonisolated func forceKill() {
        Task { @MainActor in
            await Self.shared.internalForceKill()
        }
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

    private static func openServerLogHandle() -> FileHandle? {
        guard let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/Parrot") else { return nil }
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logURL = logsDir.appendingPathComponent("llama-server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        return FileHandle(forWritingAtPath: logURL.path)
    }
}
