import Foundation

enum iCloudSyncSection: String, CaseIterable, Identifiable {
    case preferences = "Preferences"
    case history = "History"
    case customRules = "Custom Rules"

    var id: String { rawValue }
    var label: String { rawValue }
    var icon: String {
        switch self {
        case .preferences: "gearshape"
        case .history: "clock"
        case .customRules: "pencil.tip.crop.circle"
        }
    }
}

actor iCloudSyncManager {
    static let shared = iCloudSyncManager()
    private init() {}

    private var store: NSUbiquitousKeyValueStore { .default }

    var isAvailable: Bool { store.synchronize() }

    func syncToCloud(selectedSections: Set<String>) async {
        let encoded: (pref: Data?, rules: Data?, prompts: Data?, presets: Data?, flows: Data?) = await MainActor.run {
            let prefs = PreferencesStore.shared
            var prefData: Data?
            var rulesData: Data?
            var promptsData: Data?
            var presetsData: Data?
            var flowsData: Data?
            if selectedSections.contains("preferences") {
                prefData = try? JSONEncoder().encode(PreferencesExport(
                    selectedModelID: prefs.selectedModelID, language: prefs.language,
                    style: prefs.style, serviceType: prefs.serviceType,
                    autoCheckEnabled: prefs.autoCheckEnabled, realtimeEnabled: prefs.realtimeEnabled,
                    openAIBaseURL: prefs.openAIBaseURL, openAIModel: prefs.openAIModel,
                    ollamaBaseURL: prefs.ollamaBaseURL, ollamaModel: prefs.ollamaModel,
                    openRouterModel: prefs.openRouterModel, translationLanguage: prefs.translationLanguage,
                    excludedBundleIDs: prefs.excludedBundleIDs,
                    inlineAnnotationsHoverOnly: prefs.inlineAnnotationsHoverOnly,
                    aiPromptAutoDetect: prefs.aiPromptAutoDetect
                ))
            }
            if selectedSections.contains("customRules") {
                rulesData = try? JSONEncoder().encode(prefs.appRules)
                promptsData = try? JSONEncoder().encode(prefs.customPrompts)
                presetsData = try? JSONEncoder().encode(prefs.presets)
                flowsData = try? JSONEncoder().encode(prefs.flows)
            }
            return (prefData, rulesData, promptsData, presetsData, flowsData)
        }

        if let d = encoded.pref { store.set(d, forKey: "sync.preferences") }
        if let d = encoded.rules { store.set(d, forKey: "sync.appRules") }
        if let d = encoded.prompts { store.set(d, forKey: "sync.customPrompts") }
        if let d = encoded.presets { store.set(d, forKey: "sync.presets") }
        if let d = encoded.flows { store.set(d, forKey: "sync.flows") }

        if selectedSections.contains("history") {
            let entries = await HistoryStore.shared.getAllEntries()
            if let d = try? JSONEncoder().encode(entries) { store.set(d, forKey: "sync.history") }
        }

        store.synchronize()
    }

    func syncFromCloud(selectedSections: Set<String>) async -> [String] {
        var imported: [String] = []

        let prefData = store.data(forKey: "sync.preferences")
        let rulesData = store.data(forKey: "sync.appRules")
        let promptsData = store.data(forKey: "sync.customPrompts")
        let presetsData = store.data(forKey: "sync.presets")
        let flowsData = store.data(forKey: "sync.flows")
        let historyData = store.data(forKey: "sync.history")

        if selectedSections.contains("preferences"), let d = prefData,
           let p = try? JSONDecoder().decode(PreferencesExport.self, from: d) {
            await MainActor.run {
                let prefs = PreferencesStore.shared
                prefs.selectedModelID = p.selectedModelID; prefs.language = p.language
                prefs.style = p.style; prefs.serviceType = p.serviceType
                prefs.autoCheckEnabled = p.autoCheckEnabled; prefs.realtimeEnabled = p.realtimeEnabled
                prefs.openAIBaseURL = p.openAIBaseURL; prefs.openAIModel = p.openAIModel
                prefs.ollamaBaseURL = p.ollamaBaseURL; prefs.ollamaModel = p.ollamaModel
                prefs.openRouterModel = p.openRouterModel; prefs.translationLanguage = p.translationLanguage
                prefs.excludedBundleIDs = p.excludedBundleIDs
                prefs.inlineAnnotationsHoverOnly = p.inlineAnnotationsHoverOnly
                prefs.aiPromptAutoDetect = p.aiPromptAutoDetect
            }
            imported.append("preferences")
        }

        if selectedSections.contains("customRules") {
            let importedRules: [String] = await MainActor.run {
                let prefs = PreferencesStore.shared
                var keys: [String] = []
                if let d = rulesData, let r = try? JSONDecoder().decode([AppRule].self, from: d) { prefs.appRules = r; keys.append("appRules") }
                if let d = promptsData, let r = try? JSONDecoder().decode([CustomPrompt].self, from: d) { prefs.customPrompts = r; keys.append("customPrompts") }
                if let d = presetsData, let r = try? JSONDecoder().decode([Preset].self, from: d) { prefs.presets = r; keys.append("presets") }
                if let d = flowsData, let r = try? JSONDecoder().decode([Flow].self, from: d) { prefs.flows = r; keys.append("flows") }
                return keys
            }
            imported.append(contentsOf: importedRules)
        }

        if selectedSections.contains("history"), let d = historyData,
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: d) {
            await HistoryStore.shared.replaceEntries(entries)
            imported.append("history")
        }

        return imported
    }
}
