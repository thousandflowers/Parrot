import Foundation
import OSLog

/// Text-expansion snippets (abbreviation → expansion), like Cotypist's custom dictionary and
/// classic expanders. Typing a known abbreviation lets Tab expand it. Persisted as JSON in the
/// shared Application Support dir; populated by the user or imported from other apps.
actor SnippetStore {
    static let shared = SnippetStore()

    private var map: [String: String] = [:]   // abbreviation(lowercased) -> expansion
    private var loaded = false

    private static var fileURL: URL {
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Parrot")
        return dir.appendingPathComponent("snippets.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
    }

    /// Returns the expansion for an exact abbreviation match, or nil.
    func expansion(for abbreviation: String) -> String? {
        loadIfNeeded()
        let key = abbreviation.lowercased()
        guard let v = map[key], v != abbreviation else { return nil }
        return v
    }

    func count() -> Int { loadIfNeeded(); return map.count }

    /// Merges in snippets (existing keys are overwritten). Returns how many were newly added.
    @discardableResult
    func merge(_ snippets: [String: String]) -> Int {
        loadIfNeeded()
        var added = 0
        for (k, v) in snippets {
            let key = k.lowercased().trimmingCharacters(in: .whitespaces)
            let val = v
            guard !key.isEmpty, !val.isEmpty, key != val else { continue }
            if map[key] == nil { added += 1 }
            map[key] = val
        }
        save()
        return added
    }

    func all() -> [String: String] { loadIfNeeded(); return map }
    func set(_ abbr: String, _ expansion: String) { loadIfNeeded(); map[abbr.lowercased()] = expansion; save() }
    func remove(_ abbr: String) { loadIfNeeded(); map.removeValue(forKey: abbr.lowercased()); save() }

    private func save() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
