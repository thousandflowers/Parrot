import Foundation

/// Picks a debounce delay from how fast the user is typing. A long gap since the last keystroke
/// means they paused → fire fast (minMs). Rapid keystrokes → wait longer (toward maxMs) so we do
/// not burn inference on text that is about to change.
struct AdaptiveDebounce {
    let minMs: Int
    let maxMs: Int
    // Floor ~140ms: snappy ("quasi in tempo reale") but still coalesces a burst of fast keystrokes
    // into one request on the pause. Paired with a FAST model (qwen-1.5b) the request completes
    // before the next pause, so we avoid the supersede storm without making the user wait.
    init(minMs: Int = 140, maxMs: Int = 300) { self.minMs = minMs; self.maxMs = maxMs }

    func nextDelayMs(sinceLastKeystrokeMs: Int) -> Int {
        // Map [0 .. maxMs] gap → [maxMs .. minMs] delay (inverse). Clamp outside.
        if sinceLastKeystrokeMs >= maxMs { return minMs }
        if sinceLastKeystrokeMs <= 0 { return maxMs }
        let fraction = Double(sinceLastKeystrokeMs) / Double(maxMs)        // 0..1
        let delay = Double(maxMs) - fraction * Double(maxMs - minMs)
        return Int(delay.rounded())
    }
}
