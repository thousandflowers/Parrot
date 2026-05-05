import Foundation
import CryptoKit

actor ResultCache: Sendable {
    static let shared = ResultCache()

    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = Constants.cacheMaxEntries
    private let ttl = Constants.cacheTTL

    struct CacheEntry {
        let result: CorrectionResult
        let timestamp: Date
        let modelID: String
    }

    /// Generates a fixed-size hash key from text, preventing memory waste from long text keys.
    private func key(for text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    func get(for text: String, modelID: String) -> CorrectionResult? {
        let k = key(for: text)
        guard let entry = cache[k],
              entry.modelID == modelID,
              Date().timeIntervalSince(entry.timestamp) < ttl else {
            return nil
        }
        return entry.result
    }

    func set(_ result: CorrectionResult, for text: String, modelID: String) {
        let k = key(for: text)
        if cache.count >= maxEntries {
            let oldest = cache.min { $0.value.timestamp < $1.value.timestamp }
            if let key = oldest?.key { cache.removeValue(forKey: key) }
        }
        cache[k] = CacheEntry(result: result, timestamp: Date(), modelID: modelID)
    }

    func invalidateAll() {
        cache.removeAll()
    }
}
