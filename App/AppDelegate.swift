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
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        Task {
            await ServerManager.shared.stop()
            await ServerHealthMonitor.shared.stopMonitoring()
            timeoutTask.cancel()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontAppObserver = nil
        }
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let enabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !enabled {
            let alert = NSAlert()
            alert.messageText = "Permessi di Accessibilità Richiesti"
            alert.informativeText = "RefineClone necessita dell'accesso all'accessibilità per leggere e correggere il testo in altre applicazioni.\n\nApri Preferenze di Sistema > Privacy e sicurezza > Accessibilità e aggiungi RefineClone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Apri Preferenze")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
