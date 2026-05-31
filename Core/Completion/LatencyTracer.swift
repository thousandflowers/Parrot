import Foundation

/// Records per-stage latency samples and exposes percentiles. Thread-safe via a lock so it
/// can be written from the completion path and read from the diagnostics panel.
final class LatencyTracer: @unchecked Sendable {
    enum Stage: Hashable { case probe, readContext, cache, model, render, total }

    private let capacity: Int
    private var samples: [Stage: [Double]] = [:]
    private let lock = NSLock()

    init(capacity: Int = 512) { self.capacity = max(1, capacity) }

    func record(stage: Stage, milliseconds: Double) {
        lock.lock(); defer { lock.unlock() }
        var arr = samples[stage] ?? []
        arr.append(milliseconds)
        if arr.count > capacity { arr.removeFirst(arr.count - capacity) }
        samples[stage] = arr
    }

    /// Nearest-rank percentile (1-indexed, ceil). Returns 0 for an empty stage.
    /// p95 over 5 samples → the 5th (largest); p50 over 5 → the 3rd.
    func percentile(_ stage: Stage, p: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let arr = samples[stage], !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let rank = Int((p / 100.0 * Double(sorted.count)).rounded(.up))
        let idx = min(max(rank, 1), sorted.count) - 1
        return sorted[idx]
    }
}
