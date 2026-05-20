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

    private static let clipboardTokenType = NSPasteboard.PasteboardType("com.parrot.clipboard-token")

    func isElectronApp(bundleID: String) -> Bool {
        electronBundleIDs.contains(bundleID)
    }

    func extractViaClipboard(pid: pid_t) async throws -> String {
        let (originalString, originalToken) = await MainActor.run { () -> (String?, String?) in
            let pb = NSPasteboard.general
            return (pb.string(forType: .string), pb.string(forType: Self.clipboardTokenType))
        }

        _ = await MainActor.run {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.processIdentifier == pid })?
                .activate(options: [])
        }

        try? await Task.sleep(for: .milliseconds(100))

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

        var copiedText: String?
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            let (token, text) = await MainActor.run { () -> (String?, String?) in
                let pb = NSPasteboard.general
                return (pb.string(forType: Self.clipboardTokenType), pb.string(forType: .string))
            }
            if token != originalToken {
                copiedText = text
                break
            }
        }

        await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let original = originalString {
                pb.setString(original, forType: .string)
            }
            if let originalToken {
                pb.setString(originalToken, forType: Self.clipboardTokenType)
            }
        }

        guard let text = copiedText, !text.isEmpty else {
            throw CorrectionError.noTextSelected
        }
        return text
    }
}
