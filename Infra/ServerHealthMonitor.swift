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
        guard port > 0 else {
            consecutiveFailures = 0
            stopMonitoring()
            return
        }

        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        var statusCode: Int?
        var probeError: Error?
        do {
            var healthRequest = URLRequest(url: url)
            healthRequest.timeoutInterval = Constants.healthCheckTimeout
            let (_, response) = try await URLSession.shared.data(for: healthRequest)
            statusCode = (response as? HTTPURLResponse)?.statusCode
        } catch {
            probeError = error
        }
        let processAlive = await ServerManager.shared.ownProcessAlive()

        switch Self.classify(statusCode: statusCode, error: probeError, processAlive: processAlive) {
        case .healthy:
            consecutiveFailures = 0
        case .busy:
            // Slow answer (swap, long generation, model loading): not a failure — killing the
            // server here would abort the user's in-flight request.
            Logger.server.debug("Health check slow/busy (status \(statusCode ?? -1, privacy: .public)): \(probeError?.localizedDescription ?? "-", privacy: .public)")
        case .down:
            consecutiveFailures += 1
            Logger.server.info("Health check failed (\(self.consecutiveFailures, privacy: .public)/\(Constants.healthMaxConsecutiveFailures, privacy: .public)): \(probeError?.localizedDescription ?? "process not running", privacy: .public)")
            if consecutiveFailures > Constants.healthMaxConsecutiveFailures {
                await restartServer()
            }
        }
    }

    enum ProbeOutcome: Equatable {
        case healthy   // 200
        case busy      // alive but slow / loading — never counted
        case down      // connection refused or our process is dead — counted
    }

    /// Only evidence that the server is gone counts as a failure: a dead own process, or a
    /// refused / dropped connection. Timeouts and non-200 answers mean "alive but busy".
    static func classify(statusCode: Int?, error: Error?, processAlive: Bool?) -> ProbeOutcome {
        if processAlive == false { return .down }
        if statusCode == 200 { return .healthy }
        if statusCode != nil { return .busy }
        guard let urlError = error as? URLError else { return .busy }
        switch urlError.code {
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet:
            return .down
        default:
            return .busy
        }
    }

    private func restartServer() async {
        await ServerManager.shared.stop()
        guard let modelPath = ModelManager.shared.currentModelPath else {
            // Server stopped and no model to restart with → local corrections are
            // dead. Surface it instead of silently going quiet.
            Logger.server.error("ServerHealthMonitor: no model to restart with — local engine stopped")
            consecutiveFailures = 0
            await MainActor.run {
                SuggestionPanelController.shared.showError(.modelNotLoaded)
            }
            return
        }
        do {
            try await ServerManager.shared.start(modelPath: modelPath)
            consecutiveFailures = 0
            startMonitoring()
            Logger.server.info("ServerHealthMonitor: server restarted successfully")
        } catch {
            Logger.server.error("ServerHealthMonitor: restart failed — \(error.localizedDescription, privacy: .public)")
            consecutiveFailures = 0
            await MainActor.run {
                SuggestionPanelController.shared.showError(.serverTimeout)
            }
        }
    }
}
