import Foundation
import CryptoKit

/// Unified correction cache. Replaces the former ResponseCache + ResultCache.
/// Caches full CorrectionResult objects with SHA256-based keys and memory-aware eviction.
actor CorrectionCache: Sendable {
    static let shared = CorrectionCache()

    private var cache: [String: Entry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL
    private let maxMemoryBytes = Constants.cacheMaxMemoryBytes
    private var currentMemoryBytes = 0

    var currentMemoryBytesForTesting: Int { currentMemoryBytes }

    private struct Entry {
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

    // MARK: - Eviction

    private func evictUntilUnderLimit(neededBytes: Int) {
        let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
        for (key, entry) in sorted {
            guard cache.count >= maxEntries || (currentMemoryBytes + neededBytes) > maxMemoryBytes else { break }
            cache.removeValue(forKey: key)
            currentMemoryBytes = max(0, currentMemoryBytes - entry.byteSize)
        }
    }
}
