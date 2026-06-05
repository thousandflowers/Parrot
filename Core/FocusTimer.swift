import Foundation
import Combine
import OSLog

/// Single-session countdown timer for Focus Mode.
///
/// Fires a 1 Hz tick via Task.sleep. Reports elapsed/remaining time, owns the
/// word counter, and updates FocusMode.state on completion so the rest of the
/// app observes the transition. On finish it surfaces the recap panel; it does
/// NOT record stats or celebrate — that happens after the user confirms in the
/// recap (see FocusSessionView).
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum TimerState: Equatable {
        case idle
        case running(durationSeconds: Int, startTime: Date)
        case paused(elapsed: Int, remaining: Int)
        case finished
    }

    @Published var timerState: TimerState = .idle
    @Published var elapsedSeconds: Int = 0

    let wordCounter = FocusWordCounter()

    var wordsWritten: Int { wordCounter.wordsWritten }

    var remainingSeconds: Int {
        switch timerState {
        case .running(let dur, let start):
            return max(0, dur - Int(Date().timeIntervalSince(start)))
        case .paused(_, let rem):
            return rem
        default:
            return 0
        }
    }

    var isActive: Bool { if case .running = timerState { return true }; return false }
    var isPaused: Bool { if case .paused = timerState { return true }; return false }

    private var task: Task<Void, Never>?

    private init() {}

    /// Pure helper: where to place startTime when resuming so `elapsed`
    /// seconds are preserved. Testable without real time.
    static func resumeStartTime(elapsed: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(elapsed))
    }

    func start(durationMinutes: Int) {
        task?.cancel()
        let secs = durationMinutes * 60
        timerState = .running(durationSeconds: secs, startTime: .now)
        elapsedSeconds = 0
        FocusMode.shared.startSession(durationMinutes: durationMinutes)
        wordCounter.start()
        runTick()
    }

    func pause() {
        guard case .running(let dur, let start) = timerState else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        timerState = .paused(elapsed: elapsed, remaining: max(0, dur - elapsed))
        task?.cancel()
        wordCounter.pause()
    }

    func resume() {
        guard case .paused(let elapsed, let remaining) = timerState else { return }
        let dur = elapsed + remaining
        timerState = .running(durationSeconds: dur,
                              startTime: Self.resumeStartTime(elapsed: elapsed, now: .now))
        wordCounter.resumeCounting()
        runTick()
    }

    func stop() {
        task?.cancel()
        timerState = .idle
        elapsedSeconds = 0
        wordCounter.stop()
        FocusMode.shared.endSession()
    }

    /// User ended before the timer expired. If they wrote something and spent
    /// at least a minute, surface the recap so the session can be recorded;
    /// otherwise just reset.
    func endEarly() {
        let elapsed = elapsedSeconds
        task?.cancel()
        wordCounter.stop()
        FocusMode.shared.endSession()
        if wordsWritten > 0 && elapsed >= 60 {
            elapsedSeconds = elapsed
            timerState = .finished
            FocusSessionPanel.shared.show()
        } else {
            timerState = .idle
            elapsedSeconds = 0
        }
    }

    private func runTick() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard case .running(let dur, let start) = timerState else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed >= dur { finish(); return }
        elapsedSeconds = elapsed
        objectWillChange.send()
    }

    private func finish() {
        guard case .running(let dur, _) = timerState else { return }
        task?.cancel()
        wordCounter.stop()
        elapsedSeconds = dur
        timerState = .finished
        FocusMode.shared.endSession()
        objectWillChange.send()
        FocusSessionPanel.shared.show()   // surface recap; record/celebrate happen there
    }
}
