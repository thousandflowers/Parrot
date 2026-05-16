import Foundation
import AppKit
import CoreGraphics

actor ElectronFallbackHandler {
    static let shared = ElectronFallbackHandler()

    private let electronBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.slack.Slack",
        "com.discord.Discord",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "org.mozilla.firefox",
        "com.obsidian.md",
    ]

    func isElectronApp(bundleID: String) -> Bool {
        electronBundleIDs.contains(bundleID)
    }

    /// Estrae il testo selezionato sintetizzando Cmd+C e leggendo la clipboard.
    /// Ripristina la clipboard originale dopo l'estrazione.
    func extractViaClipboard(pid: pid_t) async throws -> String {
        let (originalChangeCount, originalString) = await MainActor.run { () -> (Int, String?) in
            let pb = NSPasteboard.general
            return (pb.changeCount, pb.string(forType: .string))
        }

        // Focus l'app target
        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.processIdentifier == pid })?
                .activate(options: [])
            return ()
        }

        try? await Task.sleep(for: .milliseconds(100))

        // Sintetizza Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        let cKeyCode: CGKeyCode = 0x08
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        else {
            throw CorrectionError.textExtractionFailed(appName: "Electron app")
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Attendi che la clipboard si aggiorni (max 1s)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            let (changeCount, text) = await MainActor.run { () -> (Int, String?) in
                let pb = NSPasteboard.general
                return (pb.changeCount, pb.string(forType: .string))
            }
            if changeCount != originalChangeCount {
                await MainActor.run {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    if let original = originalString {
                        pb.setString(original, forType: .string)
                    }
                }
                guard let text = text, !text.isEmpty else { break }
                return text
            }
        }

        // Ripristina clipboard originale anche in caso di fallimento
        await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let original = originalString {
                pb.setString(original, forType: .string)
            }
        }
        throw CorrectionError.noTextSelected
    }
}
