import Foundation
import AppKit
import OSLog

/// One-click migration from Cotypist. Imports the user's OWN readable data (personalization prompt,
/// completion length) and reuses Cotypist's already-downloaded GGUF models via symlink (instant, no
/// re-download, the same file → memory-mapped weights are shared). Does NOT touch Cotypist's
/// encrypted learning database — that protection is respected; Wren learns its own memory instead.
@MainActor
enum CotypistMigration {
    private static let bundleID = "app.cotypist.Cotypist"

    private static var prefsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(bundleID).plist")
    }
    private static var modelsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleID)/Models")
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: prefsURL.path)
            || FileManager.default.fileExists(atPath: "/Applications/Cotypist.app")
    }

    /// Imports settings + links models. Returns a short list of what was imported (for a confirmation).
    @discardableResult
    static func migrate() -> [String] {
        var imported: [String] = []
        let prefs = PreferencesStore.shared

        if let dict = NSDictionary(contentsOf: prefsURL) {
            if let userPrompt = dict["CompletionManager_userPrompt"] as? String,
               !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefs.completionUserPrompt = userPrompt
                imported.append("personalization")
            }
            if let maxLen = dict["CompletionManager_maxCompletionLength"] as? Int, maxLen > 0 {
                prefs.maxCompletionLength = maxLen
                imported.append("completion length")
            }
        }

        let linked = linkModels()
        if linked > 0 { imported.append("\(linked) model\(linked == 1 ? "" : "s")") }

        Logger.infra.info("CotypistMigration: imported \(imported.joined(separator: ", "), privacy: .public)")
        return imported
    }

    /// Symlinks Cotypist's GGUF models into Parrot/Wren's shared models dir (instant, shared file).
    /// If a good base model is found, selects it as the dedicated completion model.
    private static func linkModels() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: modelsDir.path) else { return 0 }
        // Shared models dir (same hardcoded "Parrot/Models" used by ModelManager → shared by both apps).
        let dest = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory).appendingPathComponent("Parrot/Models")
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)

        var linked = 0
        var baseModelID: String?
        for file in files where file.hasSuffix(".gguf") {
            let src = modelsDir.appendingPathComponent(file)
            let dst = dest.appendingPathComponent(file)
            if fm.fileExists(atPath: dst.path) { /* already there */ }
            else if (try? fm.createSymbolicLink(at: dst, withDestinationURL: src)) != nil {
                linked += 1
            }
            // Prefer a base ("-pt") model for completion.
            if file.lowercased().contains("-pt") { baseModelID = String(file.dropLast(5)) }
        }
        if let baseModelID { PreferencesStore.shared.completionModelID = baseModelID }
        return linked
    }
}
