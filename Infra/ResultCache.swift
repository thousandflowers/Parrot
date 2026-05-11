import Foundation

actor ResultCache: Sendable {
    static let shared = ResultCache()

    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL
    private let maxMemoryBytes = Constants.cacheMaxMemoryBytes
    private var currentMemoryBytes = 0

    struct CacheEntry {
        let result: CorrectionResult
        let timestamp: Date
        let modelID: String
        let byteSize: Int
    }

    func get(for text: String, modelID: String) -> CorrectionResult? {
        guard let entry = cache[text],
              entry.modelID == modelID,
              Date().timeIntervalSince(entry.timestamp) < ttl else {
            return nil
        }
        return entry.result
    }

    func set(_ result: CorrectionResult, for text: String, modelID: String) {
        let byteSize = (result.originalText.utf8.count + result.correctedText.utf8.count)

        if cache.count >= maxEntries || (currentMemoryBytes + byteSize) > maxMemoryBytes {
            evictUntilUnderLimit(neededBytes: byteSize)
        }
        cache[text] = CacheEntry(result: result, timestamp: Date(), modelID: modelID, byteSize: byteSize)
        currentMemoryBytes += byteSize
    }

    private func evictUntilUnderLimit(neededBytes: Int) {
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            guard cache.count >= maxEntries || (currentMemoryBytes + neededBytes) > maxMemoryBytes else { break }
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
        }
    }

    func invalidateAll() {
        cache.removeAll()
        currentMemoryBytes = 0
    }

    func setIfNewer(_ result: CorrectionResult, for text: String, modelID: String) {
        if let existing = cache[text], existing.timestamp >= result.timestamp { return }
        set(result, for: text, modelID: modelID)
    }
}
