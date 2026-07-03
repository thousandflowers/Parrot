import Foundation
import AppKit
import OSLog

struct ExportableSection: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

struct ExportPayload: Codable {
    let version: String
    let exportedAt: Date
    let sections: [String: Data]
}

@MainActor
final class ExportImportManager {
    static let shared = ExportImportManager()
    private init() {}

    static let availableSections: [ExportableSection] = [
        ExportableSection(id: "flows", label: "Flows", icon: "arrow.triangle.2.circlepath"),
        ExportableSection(id: "customPrompts", label: "Custom Prompts", icon: "text.quote"),
        ExportableSection(id: "presets", label: "Presets", icon: "star"),
        ExportableSection(id: "appRules", label: "App Rules", icon: "apps.iphone"),
        ExportableSection(id: "shortcuts", label: "Shortcuts", icon: "keyboard"),
        ExportableSection(id: "preferences", label: "Preferences", icon: "gearshape"),
    ]

    func export(selectedSections: Set<String>) throws -> Data {
        var sections: [String: Data] = [:]
        let prefs = PreferencesStore.shared

        if selectedSections.contains("flows") {
            sections["flows"] = try JSONEncoder().encode(prefs.flows)
        }
        if selectedSections.contains("customPrompts") {
            sections["customPrompts"] = try JSONEncoder().encode(prefs.customPrompts)
        }
        if selectedSections.contains("presets") {
            sections["presets"] = try JSONEncoder().encode(prefs.presets)
        }
        if selectedSections.contains("appRules") {
            sections["appRules"] = try JSONEncoder().encode(prefs.appRules)
        }
        if selectedSections.contains("shortcuts") {
            let config = ShortcutConfigSnapshot(
                grammar: prefs.shortcutGrammar,
                fluency: prefs.shortcutFluency,
                editor: prefs.shortcutEditor,
                replace: prefs.shortcutReplace,
                translate: prefs.shortcutTranslate,
                applyDirect: prefs.shortcutApplyDirect,
                coach: prefs.shortcutCoach,
                applyAll: prefs.shortcutApplyAll,
                grammarFluency: prefs.shortcutGrammarFluency
            )
            sections["shortcuts"] = try JSONEncoder().encode(config)
        }
        if selectedSections.contains("preferences") {
            let prefData = PreferencesExport(
                selectedModelID: prefs.selectedModelID,
                language: prefs.language,
                style: prefs.style,
                serviceType: prefs.serviceType,
                autoCheckEnabled: prefs.autoCheckEnabled,
                realtimeEnabled: prefs.realtimeEnabled,
                openAIBaseURL: prefs.openAIBaseURL,
                openAIModel: prefs.openAIModel,
                ollamaBaseURL: prefs.ollamaBaseURL,
                ollamaModel: prefs.ollamaModel,
                openRouterModel: prefs.openRouterModel,
                translationLanguage: prefs.translationLanguage,
                excludedBundleIDs: prefs.excludedBundleIDs,
                inlineAnnotationsHoverOnly: prefs.inlineAnnotationsHoverOnly,
                aiPromptAutoDetect: prefs.aiPromptAutoDetect
            )
            sections["preferences"] = try JSONEncoder().encode(prefData)
        }

        let payload = ExportPayload(
            version: "1.0",
            exportedAt: Date(),
            sections: sections
        )

        return try JSONEncoder().encode(payload)
    }

    func importData(from data: Data) throws -> [String] {
        let payload = try JSONDecoder().decode(ExportPayload.self, from: data)
        var imported: [String] = []
        let prefs = PreferencesStore.shared

        if let flowsData = payload.sections["flows"],
           let flows = try? JSONDecoder().decode([Flow].self, from: flowsData) {
            prefs.flows = flows
            imported.append("flows")
        }
        if let promptsData = payload.sections["customPrompts"],
           let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: promptsData) {
            prefs.customPrompts = prompts
            imported.append("customPrompts")
        }
        if let presetsData = payload.sections["presets"],
           let presets = try? JSONDecoder().decode([Preset].self, from: presetsData) {
            prefs.presets = presets
            imported.append("presets")
        }
        if let rulesData = payload.sections["appRules"],
           let rules = try? JSONDecoder().decode([AppRule].self, from: rulesData) {
            prefs.appRules = rules
            imported.append("appRules")
        }
        if let shortcutsData = payload.sections["shortcuts"],
           let config = try? JSONDecoder().decode(ShortcutConfigSnapshot.self, from: shortcutsData) {
            prefs.shortcutGrammar = config.grammar
            prefs.shortcutFluency = config.fluency
            prefs.shortcutEditor = config.editor
            prefs.shortcutReplace = config.replace
            prefs.shortcutTranslate = config.translate
            prefs.shortcutApplyDirect = config.applyDirect
            prefs.shortcutCoach = config.coach
            prefs.shortcutApplyAll = config.applyAll
            prefs.shortcutGrammarFluency = config.grammarFluency
            imported.append("shortcuts")
        }
        if let prefData = payload.sections["preferences"],
           let preferences = try? JSONDecoder().decode(PreferencesExport.self, from: prefData) {
            prefs.selectedModelID = preferences.selectedModelID
            prefs.language = preferences.language
            prefs.style = preferences.style
            prefs.autoCheckEnabled = preferences.autoCheckEnabled
            prefs.realtimeEnabled = preferences.realtimeEnabled
            prefs.openAIModel = preferences.openAIModel
            prefs.ollamaModel = preferences.ollamaModel
            prefs.openRouterModel = preferences.openRouterModel
            prefs.translationLanguage = preferences.translationLanguage
            prefs.excludedBundleIDs = preferences.excludedBundleIDs
            prefs.inlineAnnotationsHoverOnly = preferences.inlineAnnotationsHoverOnly
            prefs.aiPromptAutoDetect = preferences.aiPromptAutoDetect
            // SECURITY: serviceType + endpoint URLs from an imported file can silently
            // repoint the LLM backend at an attacker server, exfiltrating the user's
            // text and API key. Validate the URLs and confirm before switching backends.
            Self.applyRemoteConfig(from: preferences, into: prefs)
            imported.append("preferences")
        }

        return imported
    }

    /// Validates and applies serviceType + endpoint URLs from an imported config.
    /// Rejects non-https remote endpoints and asks the user to confirm before
    /// switching the LLM backend to an external server (exfiltration guard).
    static func applyRemoteConfig(from preferences: PreferencesExport, into prefs: PreferencesStore) {
        let openAIValid = isValidRemoteURL(preferences.openAIBaseURL, allowLoopbackHTTP: false)
        let ollamaValid = isValidRemoteURL(preferences.ollamaBaseURL, allowLoopbackHTTP: true)

        if openAIValid {
            prefs.openAIBaseURL = preferences.openAIBaseURL
        } else if !preferences.openAIBaseURL.isEmpty {
            Logger.infra.error("Import: rejected non-https openAIBaseURL")
        }
        if ollamaValid {
            prefs.ollamaBaseURL = preferences.ollamaBaseURL
        } else if !preferences.ollamaBaseURL.isEmpty {
            Logger.infra.error("Import: rejected invalid ollamaBaseURL")
        }

        let target = preferences.serviceType
        guard target == .remote || target == .ollama else {
            // stub/local/openRouter/apple/mlx use no user-supplied endpoint.
            prefs.serviceType = target
            return
        }
        let endpoint = target == .remote ? preferences.openAIBaseURL : preferences.ollamaBaseURL
        let endpointValid = target == .remote ? openAIValid : ollamaValid
        guard endpointValid else {
            Logger.infra.error("Import: not switching to \(target.rawValue, privacy: .public) — endpoint invalid")
            return
        }
        let host = URL(string: endpoint)?.host ?? endpoint
        let loopback: Set<String> = ["localhost", "127.0.0.1", "::1"]
        if loopback.contains(host.lowercased()) {
            prefs.serviceType = target
        } else if confirmRemoteSwitch(service: target.rawValue, host: host) {
            prefs.serviceType = target
        } else {
            Logger.infra.error("Import: user declined switch to external endpoint")
        }
    }

    /// Test hook for the URL-validation rule (the real method is private).
    nonisolated static func isValidRemoteURLForTest(_ string: String, allowLoopbackHTTP: Bool) -> Bool {
        isValidRemoteURL(string, allowLoopbackHTTP: allowLoopbackHTTP)
    }

    nonisolated private static func isValidRemoteURL(_ string: String, allowLoopbackHTTP: Bool) -> Bool {
        guard !string.isEmpty, let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else { return false }
        if scheme == "https" { return true }
        if scheme == "http", allowLoopbackHTTP {
            return ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        }
        return false
    }

    private static func confirmRemoteSwitch(service: String, host: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow this settings file to change your AI backend?"
        alert.informativeText = "It will send the text you correct (and your API key) to “\(host)” using the \(service) backend. Only continue if you trust the source of this file."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Keep current")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct ShortcutConfigSnapshot: Codable {
    let grammar, fluency, editor, replace: ShortcutConfig
    let translate, applyDirect, coach, applyAll: ShortcutConfig
    let grammarFluency: ShortcutConfig
}

struct PreferencesExport: Codable {
    var selectedModelID: String
    var language: String
    var style: String
    var serviceType: ServiceType
    var autoCheckEnabled: Bool
    var realtimeEnabled: Bool
    var openAIBaseURL: String
    var openAIModel: String
    var ollamaBaseURL: String
    var ollamaModel: String
    var openRouterModel: String
    var translationLanguage: String
    var excludedBundleIDs: Set<String>
    var inlineAnnotationsHoverOnly: Bool
    var aiPromptAutoDetect: Bool
}
