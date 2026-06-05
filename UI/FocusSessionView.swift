import SwiftUI

/// Session-start panel: pick duration, optional mood, start the timer.
/// Also acts as the recap view after session completion.
struct FocusSessionView: View {
    @StateObject private var timer = FocusTimer.shared
    @StateObject private var stats = FocusStatsStore.shared
    @StateObject private var focusMode = FocusMode.shared

    @State private var selectedMinutes: Int = 25
    @State private var selectedMood: String? = nil
    @State private var showRecap = false

    private let durations = [5, 10, 15, 25, 45]
    private let moods = ["😊", "😐", "😰", "🔥", "🧘"]

    var body: some View {
        VStack(spacing: 0) {
            if case .finished = timer.timerState {
                recapView
            } else if timer.isActive || timer.isPaused {
                activeSessionView
            } else {
                setupView
            }
        }
        .frame(width: 320)
        .padding()
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "target")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            Text("Focus Session")
                .font(.title2.weight(.bold))

            Text("Silence the AI. Start the timer. Write freely.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Duration picker
            HStack(spacing: 8) {
                ForEach(durations, id: \.self) { min in
                    Button(min == selectedMinutes ? "\(min)m" : "\(min)") {
                        selectedMinutes = min
                    }
                    .buttonStyle(.bordered)
                    .tint(min == selectedMinutes ? Color.accentColor : nil)
                    .controlSize(.small)
                }
            }

            // Mood picker
            VStack(spacing: 6) {
                Text("How are you feeling?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(moods, id: \.self) { m in
                        Button {
                            selectedMood = selectedMood == m ? nil : m
                        } label: {
                            Text(m)
                                .font(.title3)
                                .padding(6)
                                .background(
                                    selectedMood == m
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                timer.start(durationMinutes: selectedMinutes)
                FocusOverlayWindow.shared.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Start \(selectedMinutes) min session")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if focusMode.isRawDraft {
                Text("Completion and corrections are paused during the session.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Active session

    private var activeSessionView: some View {
        VStack(spacing: 20) {
            Button {
                timer.endEarly()
                FocusOverlayWindow.shared.hide()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("End session")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Recap

    private var recapView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Session complete!")
                .font(.title2.weight(.bold))

            HStack(spacing: 24) {
                statItem(value: "\(timer.elapsedSeconds / 60)", label: "minutes")
                statItem(value: "\(timer.wordsWritten)", label: "words")
                if stats.currentStreak > 0 {
                    statItem(value: "\(stats.currentStreak)", label: "day streak")
                }
            }

            Button("Record & continue") {
                let words = timer.wordsWritten
                let minutes = timer.elapsedSeconds / 60
                stats.recordSession(words: words, minutes: minutes, mood: selectedMood)
                FocusCelebration.shared.celebrateSessionComplete(words: words, minutes: minutes)
                timer.stop()
                FocusOverlayWindow.shared.hide()
                FocusSessionPanel.shared.close()
            }
            .buttonStyle(.borderedProminent)

            Button("Discard") {
                timer.stop()
                FocusOverlayWindow.shared.hide()
                FocusSessionPanel.shared.close()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
