import Foundation

actor ServerHealthMonitor: Sendable {
    static let shared = ServerHealthMonitor()

    private var monitorTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private let maxBackoff: TimeInterval = 60

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.healthInterval))
                await self?.checkHealth()
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkHealth() async {
        let port = await ServerManager.shared.currentPort
        guard port > 0 else { return }

        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                consecutiveFailures = 0
                return
            }
        } catch {}

        consecutiveFailures += 1
        guard consecutiveFailures <= 3 else {
            await restartServer()
            consecutiveFailures = 0
            return
        }
    }

    private func restartServer() async {
        await ServerManager.shared.stop()
        if let modelPath = await ModelManager.shared.currentModelPath {
            try? await ServerManager.shared.start(modelPath: modelPath)
        }
    }
}
