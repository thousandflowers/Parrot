import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: GlobalHotkeyManager?
    private var frontAppObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        checkAccessibilityPermissions()

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager?.registerHotkeys()
        warnFailedShortcuts()

        observeFrontmostAppChanges()

        OnboardingController.shared.showIfNeeded()

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled) {
            Task { await RealtimeMonitor.shared.start() }
        }

        // Proactively warm up the local server so first corrections don't block
        let serviceType = LLMServiceFactory.resolveDefaultServiceType()
        if serviceType == .local {
            Task { await LocalLLMService.shared.warmup() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let replyLock = NSLock()
        // Swift 6 migration: replace with Mutex (swift-synchronization) or @MainActor redesign
        nonisolated(unsafe) var didReply = false
        let replyOnce: @Sendable () -> Void = {
            replyLock.lock()
            defer { replyLock.unlock() }
            guard !didReply else { return }
            didReply = true
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            replyOnce()
        }
        Task {
            await RealtimeMonitor.shared.stop()
            await ServerManager.shared.stop()
            await ServerHealthMonitor.shared.stopMonitoring()
            timeoutTask.cancel()
            replyOnce()
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontAppObserver = nil
        }
        PreferencesStore.shared.cleanup()
    }

    private func checkAccessibilityPermissions() {
        guard shouldShowAccessibilityWarning() else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let enabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !enabled {
            let alert = NSAlert()
            alert.messageText = String(localized: "alert.accessibility.title")
            alert.informativeText = String(localized: "alert.accessibility.body")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "alert.accessibility.open_settings"))
            alert.addButton(withTitle: String(localized: "alert.accessibility.ignore"))
            alert.addButton(withTitle: String(localized: "alert.ok"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } else if response == .alertSecondButtonReturn {
                UserDefaults.standard.set(true, forKey: "hasAcknowledgedAccessibilityWarning")
            }
        }
    }

    private func shouldShowAccessibilityWarning() -> Bool {
        // Se siamo già trusted, non mostrare nulla
        if AXIsProcessTrusted() { return false }
        
        // Se l'utente ha già chiesto di non essere disturbato, rispetta la scelta
        if UserDefaults.standard.bool(forKey: "hasAcknowledgedAccessibilityWarning") { return false }
        
        return true
    }

    private func observeFrontmostAppChanges() {
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task {
                await AccessibilityBridge.shared.setLastKnownFrontAppPID(app.processIdentifier)
                await RealtimeMonitor.shared.frontAppChanged()
            }
        }
    }

    @MainActor
    private func warnFailedShortcuts() {
        guard let failed = hotkeyManager?.failedShortcuts, !failed.isEmpty else { return }
        let list = failed.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.shortcuts.title")
        alert.informativeText = String(format: String(localized: "alert.shortcuts.body_format"), list)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "alert.ok"))
        alert.runModal()
    }
}
