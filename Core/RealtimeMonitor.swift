import Foundation

actor RealtimeMonitor {
    static let shared = RealtimeMonitor()

    private var monitorTask: Task<Void, Never>?
    private var lastTextHash: Int?
    private var debounceTask: Task<Void, Never>?
    private var isEnabled = false
    private var pollInterval: TimeInterval = 5.0

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        stopInternal()
        monitorTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                let enabled = await self.isEnabled
                guard enabled else { break }
                
                let interval = await self.pollInterval
                try? await Task.sleep(for: .seconds(interval))
                
                guard !Task.isCancelled else { break }
                let stillEnabled = await self.isEnabled
                guard stillEnabled else { break }
                await self.poll()
            }
        }
    }

    func stop() {
        isEnabled = false
        stopInternal()
    }

    func frontAppChanged() {
        lastTextHash = nil
        Task { await RealtimeIndicatorController.shared.hide() }
    }

    private func stopInternal() {
        monitorTask?.cancel()
        monitorTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func poll() async {
        let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        guard pid != 0 else { 
            pollInterval = 5.0
            return 
        }
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled) else {
            pollInterval = 5.0
            return
        }

        let bundleID = await AppDetector.shared.frontAppBundleID(forPID: pid)
        if let id = bundleID {
            let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
            if excluded {
                pollInterval = 10.0 // Very conservative for excluded apps
                return
            }
        }

        guard let text = try? await fetchCurrentText(pid: pid), !text.isEmpty else { 
            pollInterval = 5.0
            return 
        }
        let hash = text.hashValue
        if hash == lastTextHash {
            // Stable text, slow down
            pollInterval = min(pollInterval + 1.0, 5.0)
            return
        }
        
        // Text changed, speed up to be responsive
        lastTextHash = hash
        pollInterval = 2.0

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await performCheck(text: text)
        }
    }

    private func fetchCurrentText(pid: pid_t) async throws -> String {
        do {
            return try await AccessibilityBridge.shared.fetchSelectedText(fromPID: pid)
        } catch CorrectionError.noTextSelected {
            let (text, _) = try await AccessibilityBridge.shared.fetchTextOrLineAtCursor(fromPID: pid)
            return text
        }
    }

    private func performCheck(text: String) async {
        guard !text.isEmpty else { return }

        do {
            let result = try await RequestQueue.shared.enqueue(
                text: text,
                type: .grammar,
                priority: .autoCheck
            )
            if result.originalText != result.correctedText {
                await RealtimeIndicatorController.shared.show(errors: true)
            } else {
                await RealtimeIndicatorController.shared.show(errors: false)
            }
        } catch {
            await RealtimeIndicatorController.shared.hide()
        }
    }
}
