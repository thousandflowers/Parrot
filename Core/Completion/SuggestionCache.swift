import Foundation

/// Small in-memory LRU mapping a context hash to a cached completion string.
/// Sits in front of the on-disk learning store to guarantee the <50ms cache path.
final class SuggestionCache: @unchecked Sendable {
    private let capacity: Int
    private var store: [String: String] = [:]
    private var order: [String] = []   // front = least recently used
    private let lock = NSLock()

    init(capacity: Int = 256) { self.capacity = max(1, capacity) }

    func get(contextHash: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let value = store[contextHash] else { return nil }
        touch(contextHash)
        return value
    }

    func set(contextHash: String, suggestion: String) {
        lock.lock(); defer { lock.unlock() }
        store[contextHash] = suggestion
        touch(contextHash)
        while order.count > capacity {
            let evict = order.removeFirst()
            store[evict] = nil
        }
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
