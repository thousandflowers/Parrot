import Foundation

actor ResultCache: Sendable {
    static let shared = ResultCache()

    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL
    private let maxMemoryBytes = Constants.cacheMaxMemoryBytes
    private var currentMemoryBytes = 0
    var currentMemoryBytesForTesting: Int { currentMemoryBytes }

    struct CacheEntry {
        let result: CorrectionResult
        let timestamp: Date
        let byteSize: Int
    }

    private func cacheKey(text: String, promptType: String, modelID: String) -> String {
        "\(promptType)|\(modelID)|\(text)"
    }

    func get(for text: String, promptType: String, modelID: String) -> CorrectionResult? {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID)
        guard let entry = cache[key] else { return nil }
        guard Date().timeIntervalSince(entry.timestamp) < ttl else {
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
            return nil
        }
        return entry.result
    }

    func set(_ result: CorrectionResult, for text: String, promptType: String, modelID: String) {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID)
        let byteSize = (result.originalText.utf8.count + result.correctedText.utf8.count)

        if let existing = cache[key] {
            currentMemoryBytes = max(0, currentMemoryBytes - existing.byteSize)
        }

        if cache.count >= maxEntries || (currentMemoryBytes + byteSize) > maxMemoryBytes {
            evictUntilUnderLimit(neededBytes: byteSize)
        }
        cache[key] = CacheEntry(result: result, timestamp: Date(), byteSize: byteSize)
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

    func setIfNewer(_ result: CorrectionResult, for text: String, promptType: String, modelID: String) {
        let key = cacheKey(text: text, promptType: promptType, modelID: modelID)
        if let existing = cache[key], existing.timestamp >= result.timestamp { return }
        set(result, for: text, promptType: promptType, modelID: modelID)
    }
}
