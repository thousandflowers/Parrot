import Foundation

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
            prefs.serviceType = preferences.serviceType
            prefs.autoCheckEnabled = preferences.autoCheckEnabled
            prefs.realtimeEnabled = preferences.realtimeEnabled
            prefs.openAIBaseURL = preferences.openAIBaseURL
            prefs.openAIModel = preferences.openAIModel
            prefs.ollamaBaseURL = preferences.ollamaBaseURL
            prefs.ollamaModel = preferences.ollamaModel
            prefs.openRouterModel = preferences.openRouterModel
            prefs.translationLanguage = preferences.translationLanguage
            prefs.excludedBundleIDs = preferences.excludedBundleIDs
            prefs.inlineAnnotationsHoverOnly = preferences.inlineAnnotationsHoverOnly
            prefs.aiPromptAutoDetect = preferences.aiPromptAutoDetect
            imported.append("preferences")
        }

        return imported
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
