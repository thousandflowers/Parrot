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

        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.autoCheckEnabled) {
            Task { await RealtimeMonitor.shared.start() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let replyLock = NSLock()
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

    func applicationWillTerminate(_ notification: Notification) {
        AccessibilityBridge.emergencyClipboardRestore()
        if let observer = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontAppObserver = nil
        }
        PreferencesStore.shared.cleanup()
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let enabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !enabled {
            let alert = NSAlert()
            alert.messageText = "Permessi di Accessibilità Richiesti"
            alert.informativeText = "RefineClone usa l'Accessibilità per leggere e correggere il testo in altre applicazioni.\n\nApri Impostazioni di Sistema > Privacy e sicurezza > Accessibilità e aggiungi RefineClone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Apri Impostazioni")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func observeFrontmostAppChanges() {
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            AccessibilityBridge.lastKnownFrontAppPID = app.processIdentifier
            Task { await RealtimeMonitor.shared.frontAppChanged() }
        }
    }

    @MainActor
    private func warnFailedShortcuts() {
        guard let failed = hotkeyManager?.failedShortcuts, !failed.isEmpty else { return }
        let list = failed.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Scorciatoie non disponibili"
        alert.informativeText = "Le seguenti scorciatoie sono gia in uso da un'altra applicazione:\n\(list)\n\nPer modificarle apri le Preferenze di RefineClone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
