import Foundation
import Darwin
import Metal

actor ServerManager: Sendable {
    static let shared = ServerManager()

    private var process: Process?
    private var startupTask: Task<Void, Error>?
    private var isExternalServer: Bool = false
    var currentPort: Int = 0

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
        // Common ports: 11434 (Ollama), 8080 (llama-server default), 11435 (RefineClone default fallback)
        let candidatePorts = [11434, 8080, 11435]
        for port in candidatePorts {
            if await checkServerHealth(port: port) {
                return port
            }
        }
        return nil
    }

    func start(modelPath: String) async throws {
        guard process == nil else { return }
        self.isExternalServer = false
        
        guard GGUFVersionCheck.isCompatible(filePath: modelPath) else {
            throw CorrectionError.modelIncompatibleVersion(path: modelPath)
        }
        
        for attempt in 0..<3 {
            let (port, probeSock) = try allocatePort()
            currentPort = port

            guard let serverURL = Bundle.main.url(forAuxiliaryExecutable: "llama-server") else {
                close(probeSock)
                currentPort = 0
                throw CorrectionError.serverNotRunning
            }

            let process = Process()
            process.executableURL = serverURL
            process.arguments = [
                "-m", modelPath,
                "--host", "127.0.0.1",
                "--port", "\(currentPort)",
                "-c", "4096",
                "--threads", "\(max(2, ProcessInfo.processInfo.processorCount / 2))",
                "--n-gpu-layers", gpuLayers(),
                "--flash-attn"
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
                for healthAttempt in 0..<20 {
                    if await checkServerHealth(port: currentPort) { return }
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
        await ServerHealthMonitor.shared.stopMonitoring()
        
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

        let deadline = Date().addingTimeInterval(5)
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
            waitpid(pid_t(pid), nil, 0)
        }
        self.process = nil
        currentPort = 0
    }

    nonisolated func forceKill() {
        Task { await stop() }
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
        addr.sin_addr.s_addr = INADDR_LOOPBACK

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
        addr.sin_addr.s_addr = INADDR_LOOPBACK
        
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
        addr.sin_addr.s_addr = INADDR_LOOPBACK
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func gpuLayers() -> String {
        guard MTLCreateSystemDefaultDevice() != nil else { return "0" }
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 16 { return "999" }
        if ramGB >= 8  { return "20" }
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
        for _ in 0..<3 {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == 0 { return true }
            if result == pid { return false }
            if result == -1 && errno == ECHILD { return false }
            if result == -1 && errno == EINTR { continue }
            return kill(pid, 0) == 0
        }
        return kill(pid, 0) == 0
    }
}
