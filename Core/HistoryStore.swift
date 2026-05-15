import Foundation
import OSLog

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let original: String
    let corrected: String
    let modelID: String
    let promptType: String
}

actor HistoryStore {
    static let shared = HistoryStore()
    private let maxEntries = 200

    private var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("RefineClone/history.json")
    }

    func add(result: CorrectionResult) {
        guard result.hasChanges else { return }
        var entries = load()
        let entry = HistoryEntry(
            id: UUID(),
            timestamp: Date(),
            original: result.originalText,
            corrected: result.correctedText,
            modelID: result.modelID,
            promptType: result.promptType
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save(entries)
    }

    func all() -> [HistoryEntry] { load() }

    func clear() { save([]) }

    private func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save(_ entries: [HistoryEntry]) {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            Logger.core.error("HistoryStore: failed to save — \(error.localizedDescription, privacy: .public)")
        }
    }
}
