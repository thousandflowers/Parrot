import Foundation
import OSLog

actor ServerHealthMonitor: Sendable {
    static let shared = ServerHealthMonitor()

    private var monitorTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    func startMonitoring() {
        stopMonitoring()
        monitorTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.healthInterval))
                guard !Task.isCancelled else { break }
                await self.checkHealth()
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    nonisolated static func forceKillMonitor() {
        Task { await shared.stopMonitoring() }
    }

    private func checkHealth() async {
        let port = await ServerManager.shared.currentPort
        guard port > 0 else { return }

        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        do {
            var healthRequest = URLRequest(url: url)
            healthRequest.timeoutInterval = 2.0
            let (_, response) = try await URLSession.shared.data(for: healthRequest)
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                consecutiveFailures = 0
                return
            }
        } catch {
            Logger.server.debug("Health check failed: \(error.localizedDescription, privacy: .public)")
        }

        consecutiveFailures += 1
        guard consecutiveFailures <= 3 else {
            await restartServer()
            return
        }
    }

    private func restartServer() async {
        await ServerManager.shared.stop()
        guard let modelPath = ModelManager.shared.currentModelPath else { return }
        do {
            try await ServerManager.shared.start(modelPath: modelPath)
            consecutiveFailures = 0
            startMonitoring()
            Logger.server.info("ServerHealthMonitor: server restarted successfully")
        } catch {
            Logger.server.error("ServerHealthMonitor: restart failed — \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                SuggestionPanelController.shared.showError(.serverTimeout)
            }
        }
    }
}
