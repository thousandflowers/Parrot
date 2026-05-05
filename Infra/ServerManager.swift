import Foundation
import Darwin

actor ServerManager: Sendable {
    static let shared = ServerManager()

    private var process: Process?
    var currentPort: Int = 0

    func start(modelPath: String) async throws {
        currentPort = try allocatePort()

        guard let serverURL = Bundle.main.url(forAuxiliaryExecutable: "llama-server") else {
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
            "--n-gpu-layers", gpuLayers(),  // Auto-detect based on available RAM
            "--flash-attn"
        ]

        do {
            try process.run()
        } catch {
            throw CorrectionError.serverNotRunning
        }
        self.process = process

        for _ in 0..<30 {
            if await checkServerHealth() { return }
            try await Task.sleep(for: .milliseconds(500))
        }

        process.terminate()
        self.process = nil
        throw CorrectionError.serverTimeout
    }

    func stop() async {
        guard let process = process else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if process.isRunning {
            kill(pid_t(process.processIdentifier), SIGKILL)
        }
        self.process = nil
    }

    /// Allocates a kernel-assigned port via bind(0) — no TOCTOU race.
    private func allocatePort() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw CorrectionError.serverNotRunning }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

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
        close(sock)
        return port
    }

    /// Auto-detect GPU layers: 999 on 16GB+, 20 on 8-15GB, 0 on <8GB
    private func gpuLayers() -> String {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 16 { return "999" }
        if ramGB >= 8  { return "20" }
        return "0"
    }

private func checkServerHealth() async -> Bool {
        guard currentPort > 0 else { return false }
        let url = URL(string: "http://127.0.0.1:\(currentPort)/health")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
