import Foundation

struct UndoEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let originalText: String
    let replacedText: String
    let bundleID: String?
    let timestamp: Date

    var displayLabel: String {
        let app = bundleID?.split(separator: ".").last.map(String.init) ?? "App"
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let time = formatter.localizedString(for: timestamp, relativeTo: Date())
        return "\(app) — \(time)"
    }
}

actor UndoHistoryStore {
    static let shared = UndoHistoryStore()

    private static let maxEntries = 20
    private let fileURL: URL
    private var entries: [UndoEntry] = []

    init() {
        let appSupport = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Parrot")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("undo_history.json")
        let data = try? Data(contentsOf: fileURL)
        entries = data.flatMap { try? JSONDecoder().decode([UndoEntry].self, from: $0) } ?? []
        entries = Array(entries.prefix(Self.maxEntries))
    }

    func add(_ entry: UndoEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast()
        }
        save()
    }

    func latest() -> UndoEntry? {
        entries.first
    }

    func all() -> [UndoEntry] {
        entries
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
