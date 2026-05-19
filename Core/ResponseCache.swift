import Foundation

final class ResponseCache: @unchecked Sendable {
    static let shared = ResponseCache()

    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()

    private struct CacheEntry {
        let result: String
        let timestamp: Date
    }

    func get(text: String, model: String, promptType: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        let key = "\(promptType)|\(model)|\(text)"
        guard let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < Constants.cacheTTL else {
            if cache[key] != nil { cache.removeValue(forKey: key) }
            return nil
        }
        return entry.result
    }

    func set(text: String, model: String, promptType: String, result: String) {
        lock.lock(); defer { lock.unlock() }
        let key = "\(promptType)|\(model)|\(text)"
        cache[key] = CacheEntry(result: result, timestamp: Date())
        if cache.count > Constants.cacheMaxEntries {
            if let oldest = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) {
                cache.removeValue(forKey: oldest.key)
            }
        }
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }

    func invalidate(model: String) {
        lock.lock(); defer { lock.unlock() }
        let needle = "|\(model)|"
        cache = cache.filter { !$0.key.contains(needle) }
    }
}
