import Foundation
import Darwin
import Metal

actor ServerManager: Sendable {
    static let shared = ServerManager()

    private var process: Process?
    private var startupTask: Task<Void, Error>?
    var currentPort: Int = 0

    func ensureRunning(modelPath: String) async throws -> Int {
        if let existingTask = startupTask {
            try await existingTask.value
            return currentPort
        }
        if currentPort > 0 { return currentPort }

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

    func start(modelPath: String) async throws {
        guard process == nil else { return }
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
                    if await checkServerHealth() { return }
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

    /// Auto-detect GPU layers: 999 on 16GB+, 20 on 8-15GB, 0 on <8GB or no Metal GPU
    private func gpuLayers() -> String {
        guard MTLCreateSystemDefaultDevice() != nil else { return "0" }
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 16 { return "999" }
        if ramGB >= 8  { return "20" }
        return "0"
    }

    private func checkServerHealth() async -> Bool {
        guard currentPort > 0 else { return false }
        guard let url = URL(string: "http://127.0.0.1:\(currentPort)/health") else {
            return false
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
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
