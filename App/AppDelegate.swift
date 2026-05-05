import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: GlobalHotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        checkAccessibilityPermissions()

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager?.registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Graceful shutdown: stop llama-server (SIGTERM first, SIGKILL after 5s)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await ServerManager.shared.stop()
            semaphore.signal()
        }
        // macOS grants ~5 seconds before forcing termination
        _ = semaphore.wait(timeout: .now() + 5)
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let enabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !enabled {
            let alert = NSAlert()
            alert.messageText = "Permessi di Accessibilita Richiesti"
            alert.informativeText = "RefineClone necessita dell'accesso all'accessibilita per leggere e correggere il testo in altre applicazioni.\n\nApri Preferenze di Sistema > Privacy e sicurezza > Accessibilita e aggiungi RefineClone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Apri Preferenze")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}
