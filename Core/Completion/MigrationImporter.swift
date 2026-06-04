import Foundation
import OSLog

/// Imports as much of the user's own data as possible from other apps so Wren can replace them:
/// macOS Text Replacements, espanso, Cotypist (settings + models). Only reads accessible, plain
/// data — never circumvents another app's encryption.
@MainActor
enum MigrationImporter {
    struct Result { var lines: [String] = [] }

    static func importAll() async -> Result {
        var result = Result()

        // 1. macOS system Text Replacements → snippets.
        let sys = macOSTextReplacements()
        if !sys.isEmpty {
            let n = await SnippetStore.shared.merge(sys)
            result.lines.append("\(sys.count) macOS text replacements (\(n) new)")
        }

        // 2. espanso matches → snippets.
        let esp = espansoMatches()
        if !esp.isEmpty {
            let n = await SnippetStore.shared.merge(esp)
            result.lines.append("\(esp.count) espanso snippets (\(n) new)")
        }

        // 3. Cotypist: personalization, length, models.
        if CotypistMigration.isAvailable {
            let imported = CotypistMigration.migrate()
            if !imported.isEmpty { result.lines.append("Cotypist: " + imported.joined(separator: ", ")) }
            // Cotypist's clipboard-context preference.
            if let dict = NSDictionary(contentsOf: cotypistPrefs),
               let clip = dict["TextFieldContextCapture_pasteboardContextEnabled"] as? Bool, clip {
                PreferencesStore.shared.completionUseClipboardContext = true
            }
        }

        if result.lines.isEmpty { result.lines.append("Nothing found to import.") }
        Logger.infra.info("MigrationImporter: \(result.lines.joined(separator: "; "), privacy: .public)")
        return result
    }

    // MARK: - Sources

    private static func macOSTextReplacements() -> [String: String] {
        guard let items = UserDefaults.standard.array(forKey: "NSUserDictionaryReplacementItems") as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for item in items {
            if let replace = item["replace"] as? String, let with = item["with"] as? String,
               !replace.isEmpty, !with.isEmpty { out[replace] = with }
        }
        return out
    }

    private static func espansoMatches() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [
            home.appendingPathComponent("Library/Application Support/espanso/match"),
            home.appendingPathComponent(".config/espanso/match"),
        ]
        var out: [String: String] = [:]
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "yml" || f.pathExtension == "yaml" {
                guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
                out.merge(parseEspanso(text)) { _, new in new }
            }
        }
        return out
    }

    /// Minimal espanso YAML parser: pairs `trigger:`/`replace:` lines. Handles the common shape.
    nonisolated static func parseEspanso(_ yaml: String) -> [String: String] {
        var out: [String: String] = [:]
        var pendingTrigger: String?
        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            func value(after key: String) -> String? {
                guard line.hasPrefix(key) else { return nil }
                var v = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")), v.count >= 2 {
                    v = String(v.dropFirst().dropLast())
                }
                return v.isEmpty ? nil : v
            }
            if let t = value(after: "- trigger:") ?? value(after: "trigger:") { pendingTrigger = t }
            else if let r = value(after: "replace:"), let t = pendingTrigger {
                out[t] = r.replacingOccurrences(of: "\\n", with: "\n")
                pendingTrigger = nil
            }
        }
        return out
    }

    private static var cotypistPrefs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/app.cotypist.Cotypist.plist")
    }

    /// True if any importable source exists.
    static var hasAnySource: Bool {
        CotypistMigration.isAvailable
            || (UserDefaults.standard.array(forKey: "NSUserDictionaryReplacementItems")?.isEmpty == false)
            || FileManager.default.fileExists(atPath:
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/espanso/match").path)
    }
}
