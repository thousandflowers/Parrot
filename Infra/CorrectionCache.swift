import Foundation
import CryptoKit
import OSLog

actor CorrectionCache: Sendable {
    static let shared = CorrectionCache()

    private var cache: [String: Entry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL
    private let maxMemoryBytes = Constants.cacheMaxMemoryBytes
    private var currentMemoryBytes = 0
    private var pendingSave: Task<Void, Error>?

    var currentMemoryBytesForTesting: Int { currentMemoryBytes }

    let cacheFileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Parrot/correction_cache.json")
    }()

    private struct Entry {
        let result: CorrectionResult
        let timestamp: Date
        let byteSize: Int
    }

    private struct DiskEntry: Codable {
        let key: String
        let result: CorrectionResult
        let timestamp: Date
        let byteSize: Int
    }

    // MARK: - Key generation

    private func cacheKey(text: String, promptType: String, modelID: String, language: String) -> String {
        let textHash: String
        if let data = text.data(using: .utf8) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            textHash = String(hex.prefix(32))
        } else {
            textHash = String(text.hashValue)
        }
        return "\(promptType)|\(language)|\(modelID)|\(textHash)"
    }

    // MARK: - Public API

    func get(text: String, promptType: String, modelID: String, language: String = "") -> CorrectionResult? {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        guard let entry = cache[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
            return nil
        }
        return entry.result
    }

    func set(_ result: CorrectionResult, text: String, promptType: String, modelID: String, language: String = "") {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        let byteSize = result.originalText.utf8.count + result.correctedText.utf8.count

        if let existing = cache[key] {
            currentMemoryBytes = max(0, currentMemoryBytes - existing.byteSize)
        }
        if cache.count >= maxEntries || (currentMemoryBytes + byteSize) > maxMemoryBytes {
            evictUntilUnderLimit(neededBytes: byteSize)
        }
        cache[key] = Entry(result: result, timestamp: Date(), byteSize: byteSize)
        currentMemoryBytes += byteSize
        scheduleSave()
    }

    func setIfNewer(_ result: CorrectionResult, text: String, promptType: String, modelID: String, language: String = "") {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID, language: language)
        if let existing = cache[key], existing.timestamp >= result.timestamp { return }
        set(result, text: text, promptType: promptType, modelID: modelID, language: language)
    }

    func invalidateAll() {
        cache.removeAll()
        currentMemoryBytes = 0
    }

    func invalidate(model: String) {
        let needle = "|\(model)|"
        let keysToRemove = cache.keys.filter { $0.contains(needle) }
        for key in keysToRemove {
            if let entry = cache[key] {
                currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
            }
            cache.removeValue(forKey: key)
        }
    }

    // MARK: - Disk persistence

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let entries = try? JSONDecoder().decode([DiskEntry].self, from: data) else { return }
        let now = Date()
        var loaded = 0
        for entry in entries {
            guard now.timeIntervalSince(entry.timestamp) < ttl else { continue }
            cache[entry.key] = Entry(result: entry.result, timestamp: entry.timestamp, byteSize: entry.byteSize)
            currentMemoryBytes += entry.byteSize
            loaded += 1
        }
        if cache.count > maxEntries || currentMemoryBytes > maxMemoryBytes {
            evictUntilUnderLimit(neededBytes: 0)
        }
        Logger.infra.debug("CorrectionCache: loaded \(loaded) entries from disk")
    }

    func saveToDisk() {
        let entries = cache.map { (key, entry) in
            DiskEntry(key: key, result: entry.result, timestamp: entry.timestamp, byteSize: entry.byteSize)
        }
        let url = cacheFileURL
        Task(priority: .utility) {
            guard let data = try? JSONEncoder().encode(entries) else { return }
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func deleteCacheFile() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    // MARK: - Eviction

    private func evictUntilUnderLimit(neededBytes: Int) {
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            guard cache.count >= maxEntries || (currentMemoryBytes + neededBytes) > maxMemoryBytes else { break }
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
        }
    }

    // MARK: - Debounced save

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try await Task.sleep(for: .seconds(30))
            self.saveToDisk()
        }
    }
}
