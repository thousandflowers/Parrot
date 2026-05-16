import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: GlobalHotkeyManager?
    private var frontAppObserver: NSObjectProtocol?
    private var windowObservers: [Any] = []
    private var realtimeStartTask: Task<Void, Never>?
    private var serverPreWarmTask: Task<Void, Never>?
    private var detectOllamaTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashLogger.install()
        showOnboardingIfFirstLaunch()
        NSApp.setActivationPolicy(.accessory)

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager?.registerHotkeys()
        warnFailedShortcuts()

        observeFrontmostAppChanges()
        setupDockIconManagement()

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled) {
            realtimeStartTask = Task { await RealtimeMonitor.shared.start() }
        }

        // Pre-warm llama-server in background so the first correction request is instant
        if LLMServiceFactory.resolveDefaultServiceType() == .local,
           let modelPath = ModelManager.shared.currentModelPath {
            serverPreWarmTask = Task { try? await ServerManager.shared.ensureRunning(modelPath: modelPath) }
        }

        detectOllamaTask = Task { await detectOllama() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "refineclone",
                  url.host == "correct" else { continue }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let textParam = components.queryItems?.first(where: { $0.name == "text" })?.value,
                  !textParam.isEmpty else { continue }
            Task { @MainActor in
                let result = try? await RequestQueue.shared.enqueue(
                    text: textParam, type: .grammar, priority: .manual
                )
                if let r = result {
                    SuggestionPanelController.shared.show(result: r)
                }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let replyLock = NSLock()
        nonisolated(unsafe) var didReply = false
        let replyOnce: @Sendable () -> Void = {
            replyLock.lock(); defer { replyLock.unlock() }
            guard !didReply else { return }
            didReply = true
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        let timeout = Task { try? await Task.sleep(for: .seconds(10)); replyOnce() }
        Task {
            await RealtimeMonitor.shared.stop()
            await ServerManager.shared.stop()
            await ServerHealthMonitor.shared.stopMonitoring()
            timeout.cancel()
            replyOnce()
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        AccessibilityBridge.emergencyClipboardRestore()
        if let obs = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            frontAppObserver = nil
        }
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        PreferencesStore.shared.cleanup()
    }

    // MARK: - Dock icon: show when a settings window is open, hide otherwise

    private func setupDockIconManagement() {
        let nc = NotificationCenter.default
        windowObservers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            AppDelegate.updateDockVisibility()
        })
        windowObservers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AppDelegate.updateDockVisibility() }
        })
    }

    static func updateDockVisibility() {
        let hasRegularWindow = NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible && $0.canBecomeMain }
        if hasRegularWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Front app tracking

    private func observeFrontmostAppChanges() {
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            AccessibilityBridge.lastKnownFrontAppPID = app.processIdentifier
            Task { await RealtimeMonitor.shared.frontAppChanged() }
        }
    }

    private func showOnboardingIfFirstLaunch() {
        let key = "RefineClone.hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let hostingCtrl = NSHostingController(rootView: OnboardingView())
        let window = NSWindow(contentViewController: hostingCtrl)
        window.title = "Benvenuto"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        hostingCtrl.rootView.onDismiss = { [weak window] in
            window?.close()
        }
    }

    private func detectOllama() async {
        let url = URL(string: "http://localhost:11434/api/tags")!
        var detected = false
        do {
            var req = URLRequest(url: url, timeoutInterval: 3)
            req.httpMethod = "GET"
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                detected = true
                let modelNames = models.compactMap { $0["name"] as? String }.joined(separator: ", ")
                CrashLogger.log("Ollama rilevato su localhost:11434 – modelli: \(modelNames)")
            }
        } catch {
            CrashLogger.log("Ollama non rilevato su localhost:11434 – \(error.localizedDescription)")
        }
        if !detected, LLMServiceFactory.resolveDefaultServiceType() == .ollama {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Ollama non rilevato"
                alert.informativeText = "Il service è configurato per usare Ollama (localhost:11434), ma il server non risulta in esecuzione. Avvia Ollama o modifica il service nelle Preferenze."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @MainActor
    private func warnFailedShortcuts() {
        guard let failed = hotkeyManager?.failedShortcuts, !failed.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Scorciatoie non disponibili"
        alert.informativeText = "Le seguenti scorciatoie sono già in uso:\n\(failed.joined(separator: ", "))\n\nModificale nelle Preferenze."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
