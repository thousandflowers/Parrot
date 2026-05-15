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
            let (_, response) = try await URLSession.shared.data(from: url)
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
            consecutiveFailures = 0
            return
        }
    }

    private func restartServer() async {
        await ServerManager.shared.stop()
        guard let modelPath = ModelManager.shared.currentModelPath else { return }
        Task {
            do {
                try await ServerManager.shared.start(modelPath: modelPath)
                startMonitoring()
                Logger.server.info("ServerHealthMonitor: server restarted successfully")
            } catch {
                Logger.server.error("ServerHealthMonitor: restart failed — \(error.localizedDescription, privacy: .public)")
            }
        }
        await MainActor.run {
            SuggestionPanelController.shared.showError(.serverTimeout)
        }
    }
}
