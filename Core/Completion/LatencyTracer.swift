import Foundation

/// Records per-stage latency samples and exposes percentiles. Thread-safe via a lock so it
/// can be written from the completion path and read from the diagnostics panel.
final class LatencyTracer: @unchecked Sendable {
    enum Stage: String, Hashable, CaseIterable { case probe, readContext, cache, model, render, total }

    /// Shared instance the live completion path records into; read by the diagnostics panel.
    static let shared = LatencyTracer()

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

    /// Number of recorded samples for a stage.
    func count(_ stage: Stage) -> Int {
        lock.lock(); defer { lock.unlock() }
        return samples[stage]?.count ?? 0
    }

    /// Markdown table of p50/p95/p99 (ms) per stage with a sample count. Empty stages are skipped.
    /// Suitable to paste into the README "Performance" section.
    func report() -> String {
        var lines = ["| Stage | p50 | p95 | p99 | n |", "|---|---|---|---|---|"]
        for stage in Stage.allCases {
            let n = count(stage)
            guard n > 0 else { continue }
            let p50 = percentile(stage, p: 50)
            let p95 = percentile(stage, p: 95)
            let p99 = percentile(stage, p: 99)
            lines.append(String(format: "| %@ | %.0f ms | %.0f ms | %.0f ms | %d |",
                                stage.rawValue, p50, p95, p99, n))
        }
        return lines.count > 2 ? lines.joined(separator: "\n") : "No samples yet — type in any app with completion on, then re-check."
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll()
    }
}
