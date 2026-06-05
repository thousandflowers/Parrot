import Foundation

/// Controls Wren's focus-mode state machine.
///
/// OFF        — normal Wren (completion + correction active)
/// RAW_DRAFT  — all AI suggestions suspended, user writes freely
/// SESSION    — timer running, automatically in raw draft mode
///
/// FocusMode.shared.isRawDraft is the single gate that CompletionController,
/// RealtimeMonitor, and TextCheckCoordinator should check.
@MainActor
final class FocusMode: ObservableObject {
    static let shared = FocusMode()

    enum State: Equatable {
        case off
        case rawDraft
        case session(duration: Int, startTime: Date)
    }

    @Published var state: State = .off

    var isRawDraft: Bool {
        if case .off = state { return false }
        return true
    }

    var isSession: Bool {
        if case .session = state { return true }
        return false
    }

    func enterRawDraft() {
        guard !isSession else { return }  // session is a superset
        state = .rawDraft
    }

    func exitRawDraft() {
        guard !isSession else { return }
        state = .off
    }

    func startSession(durationMinutes: Int) {
        state = .session(duration: durationMinutes * 60, startTime: .now)
    }

    func endSession() {
        state = .off
    }

    func toggleRawDraft() {
        if isRawDraft { exitRawDraft() }
        else { enterRawDraft() }
    }
}
