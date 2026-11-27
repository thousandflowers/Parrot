import Foundation
import OSLog

extension Notification.Name {
    static let historyDidChange = Notification.Name("historyDidChange")
}

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
    private var cachedEntries: [HistoryEntry]?
    private let historyURL: URL

    private init() {
        let appSupport = AppPaths.applicationSupport
            ?? FileManager.default.temporaryDirectory
        self.init(fileURL: appSupport.appendingPathComponent("Parrot/history.json"))
    }

    /// Injectable location so tests never touch the user's real history.
    init(fileURL: URL) {
        historyURL = fileURL
    }

    func add(result: CorrectionResult) {
        guard result.hasChanges else { return }
        var entries = cachedEntries ?? load()
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
        cachedEntries = entries
        save(entries)
        NotificationCenter.default.post(name: .historyDidChange, object: nil)
    }

    func all() -> [HistoryEntry] {
        let entries = cachedEntries ?? load()
        cachedEntries = entries
        return entries
    }

    func getAllEntries() -> [HistoryEntry] { all() }

    func replaceEntries(_ entries: [HistoryEntry]) {
        cachedEntries = entries
        save(entries)
        NotificationCenter.default.post(name: .historyDidChange, object: nil)
    }

    func clear() {
        cachedEntries = []
        save([])
    }

    private func load() -> [HistoryEntry] {
        PersistentJSON.load([HistoryEntry].self, from: historyURL) ?? []
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
