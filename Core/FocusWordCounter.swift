import Foundation

/// Counts words the user types during a focus session by diffing the focused
/// field's word count over time. Positive deltas accumulate; small negative
/// deltas (backspace) are ignored; large drops (field/app switch) rebase the
/// baseline without subtracting.
///
/// The delta logic (`processReading`/`baseline`/`rebaseline`) is pure and
/// synchronous so it unit-tests without Accessibility. The AX poll loop lives
/// in `start()`/`stop()` and feeds readings into `processReading`.
@MainActor
final class FocusWordCounter: ObservableObject {

    /// Word-count drop larger than this (in words) is treated as a field switch.
    static let rebaseThreshold = 5

    @Published private(set) var wordsWritten: Int = 0
    private var lastCount: Int = 0

    private var pollTask: Task<Void, Never>?

    // MARK: - Pure core (testable)

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Reset accumulated words and set the starting baseline.
    func baseline(count: Int) {
        wordsWritten = 0
        lastCount = count
    }

    /// Move the baseline to `count` without changing accumulated words.
    func rebaseline(count: Int) {
        lastCount = count
    }

    /// Feed a fresh word-count reading and update `wordsWritten`.
    func processReading(count: Int) {
        let delta = count - lastCount
        if delta > 0 {
            wordsWritten += delta
        }
        // delta <= 0: backspace (small) or field switch (large) — either way
        // we only rebase lastCount, never subtract.
        lastCount = count
    }

    // MARK: - AX poll lifecycle

    /// Reset, take an initial baseline from the focused field, and start polling.
    func start() {
        pollTask?.cancel()
        wordsWritten = 0
        Task { [weak self] in
            await self?.takeBaseline()
            self?.runPoll()
        }
    }

    /// Re-arm polling after a pause without zeroing accumulated words.
    /// Re-baselines to the current field on the next read.
    func resumeCounting() {
        pollTask?.cancel()
        Task { [weak self] in
            await self?.takeBaseline()        // rebaseline only; wordsWritten preserved
            self?.runPoll()
        }
    }

    /// Stop polling. `wordsWritten` keeps its final value.
    func pause() { pollTask?.cancel(); pollTask = nil }
    func stop()  { pollTask?.cancel(); pollTask = nil }

    private func takeBaseline() async {
        let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
        let text = await AccessibilityBridge.shared.focusedPlainText(pid: pid)
        lastCount = text.map { Self.wordCount($0) } ?? lastCount
    }

    private func runPoll() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
                guard let text = await AccessibilityBridge.shared.focusedPlainText(pid: pid)
                else { continue }   // read failed — leave state unchanged
                self.processReading(count: Self.wordCount(text))
            }
        }
    }
}
