import Foundation
import OSLog

/// Sync sections. `rawValue` is the stable key used by the UI selection and by the sync
/// logic — never derive it from the display label.
enum iCloudSyncSection: String, CaseIterable, Identifiable, Hashable {
    case preferences
    case history
    case customRules

    var id: String { rawValue }
    var label: String {
        switch self {
        case .preferences: "Preferences"
        case .history: "History"
        case .customRules: "Custom Rules"
        }
    }
    var icon: String {
        switch self {
        case .preferences: "gearshape"
        case .history: "clock"
        case .customRules: "pencil.tip.crop.circle"
        }
    }
}

/// Outcome of an upload: what reached the key-value store and what did not (with why).
struct iCloudUploadReport: Sendable {
    struct Failure: Sendable {
        let key: String
        let reason: String
    }
    let uploaded: [String]
    let failed: [Failure]
}

actor iCloudSyncManager {
    static let shared = iCloudSyncManager()
    private init() {}

    private var store: NSUbiquitousKeyValueStore { .default }

    var isAvailable: Bool { store.synchronize() }

    private typealias Encoded = Result<Data, Error>

    func syncToCloud(selectedSections: Set<iCloudSyncSection>) async -> iCloudUploadReport {
        var candidates: [(key: String, value: Encoded)] = await MainActor.run {
            let prefs = PreferencesStore.shared
            var items: [(key: String, value: Encoded)] = []
            if selectedSections.contains(.preferences) {
                items.append(("sync.preferences", Self.encode(PreferencesExport(
                    selectedModelID: prefs.selectedModelID, language: prefs.language,
                    style: prefs.style, serviceType: prefs.serviceType,
                    autoCheckEnabled: prefs.autoCheckEnabled, realtimeEnabled: prefs.realtimeEnabled,
                    openAIBaseURL: prefs.openAIBaseURL, openAIModel: prefs.openAIModel,
                    ollamaBaseURL: prefs.ollamaBaseURL, ollamaModel: prefs.ollamaModel,
                    openRouterModel: prefs.openRouterModel, translationLanguage: prefs.translationLanguage,
                    excludedBundleIDs: prefs.excludedBundleIDs,
                    inlineAnnotationsHoverOnly: prefs.inlineAnnotationsHoverOnly,
                    aiPromptAutoDetect: prefs.aiPromptAutoDetect
                ))))
            }
            if selectedSections.contains(.customRules) {
                items.append(("sync.appRules", Self.encode(prefs.appRules)))
                items.append(("sync.customPrompts", Self.encode(prefs.customPrompts)))
                items.append(("sync.presets", Self.encode(prefs.presets)))
                items.append(("sync.flows", Self.encode(prefs.flows)))
            }
            return items
        }
        if selectedSections.contains(.history) {
            candidates.append(("sync.history", Self.encode(await HistoryStore.shared.getAllEntries())))
        }

        var failed: [iCloudUploadReport.Failure] = []
        var encoded: [(key: String, data: Data)] = []
        for candidate in candidates {
            switch candidate.value {
            case .success(let data): encoded.append((candidate.key, data))
            case .failure(let error): failed.append(.init(key: candidate.key, reason: "could not encode: \(error.localizedDescription)"))
            }
        }

        let existing = store.dictionaryRepresentation.reduce(into: [String: Int]()) { sizes, entry in
            sizes[entry.key] = entry.key.utf8.count + ((entry.value as? Data)?.count ?? 0)
        }
        let plan = Self.planUpload(candidates: encoded, existingSizes: existing, limitBytes: Constants.iCloudKVSMaxBytes)
        failed += plan.rejected
        plan.accepted.forEach { store.set($0.data, forKey: $0.key) }

        var uploaded = plan.accepted.map(\.key)
        if !uploaded.isEmpty, !store.synchronize() {
            failed += uploaded.map { .init(key: $0, reason: "iCloud synchronize failed (signed out or no entitlement)") }
            uploaded = []
        }
        failed.forEach { Logger.infra.error("iCloud upload: \($0.key, privacy: .public) not uploaded — \($0.reason, privacy: .public)") }
        return iCloudUploadReport(uploaded: uploaded, failed: failed)
    }

    /// Splits values into those that fit the key-value store and those that would be silently
    /// dropped by it: each value (key + data) ≤ `limitBytes`, and the whole store (other keys
    /// already there + these) ≤ `limitBytes`. Values replacing an existing key free its old size.
    static func planUpload(candidates: [(key: String, data: Data)], existingSizes: [String: Int],
                           limitBytes: Int) -> (accepted: [(key: String, data: Data)], rejected: [iCloudUploadReport.Failure]) {
        let candidateKeys = Set(candidates.map(\.key))
        var total = existingSizes.filter { !candidateKeys.contains($0.key) }.values.reduce(0, +)
        var accepted: [(key: String, data: Data)] = []
        var rejected: [iCloudUploadReport.Failure] = []
        let fmt = { (bytes: Int) in ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
        for candidate in candidates {
            let size = candidate.key.utf8.count + candidate.data.count
            if size > limitBytes {
                rejected.append(.init(key: candidate.key, reason: "\(fmt(size)) exceeds the iCloud limit of \(fmt(limitBytes)) per item"))
            } else if total + size > limitBytes {
                rejected.append(.init(key: candidate.key, reason: "iCloud storage for this app is full (\(fmt(limitBytes)) total)"))
            } else {
                accepted.append(candidate)
                total += size
            }
        }
        return (accepted, rejected)
    }

    private nonisolated static func encode<T: Encodable>(_ value: T) -> Encoded {
        Result { try JSONEncoder().encode(value) }
    }

    func syncFromCloud(selectedSections: Set<iCloudSyncSection>) async -> [String] {
        var imported: [String] = []

        let prefData = store.data(forKey: "sync.preferences")
        let rulesData = store.data(forKey: "sync.appRules")
        let promptsData = store.data(forKey: "sync.customPrompts")
        let presetsData = store.data(forKey: "sync.presets")
        let flowsData = store.data(forKey: "sync.flows")
        let historyData = store.data(forKey: "sync.history")

        if selectedSections.contains(.preferences), let d = prefData,
           let p = Self.decode(PreferencesExport.self, from: d, key: "sync.preferences") {
            // Same validated path as file import: endpoint URLs are checked and switching to an
            // external backend needs the user's confirmation.
            await MainActor.run {
                ExportImportManager.applyPreferences(p, into: PreferencesStore.shared, source: "iCloud data")
            }
            imported.append("preferences")
        }

        if selectedSections.contains(.customRules) {
            let importedRules: [String] = await MainActor.run {
                let prefs = PreferencesStore.shared
                var keys: [String] = []
                if let d = rulesData, let r = Self.decode([AppRule].self, from: d, key: "sync.appRules") { prefs.appRules = r; keys.append("appRules") }
                if let d = promptsData, let r = Self.decode([CustomPrompt].self, from: d, key: "sync.customPrompts") { prefs.customPrompts = r; keys.append("customPrompts") }
                if let d = presetsData, let r = Self.decode([Preset].self, from: d, key: "sync.presets") { prefs.presets = r; keys.append("presets") }
                if let d = flowsData, let r = Self.decode([Flow].self, from: d, key: "sync.flows") { prefs.flows = r; keys.append("flows") }
                return keys
            }
            imported.append(contentsOf: importedRules)
        }

        if selectedSections.contains(.history), let d = historyData,
           let entries = Self.decode([HistoryEntry].self, from: d, key: "sync.history") {
            await HistoryStore.shared.replaceEntries(entries)
            imported.append("history")
        }

        return imported
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data, key: String) -> T? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger.infra.error("iCloud download: cannot decode \(key, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
