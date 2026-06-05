import SwiftUI

/// Settings tab for Focus Mode configuration.
struct FocusTab: View {
    @Bindable var prefs: PreferencesStore
    @StateObject private var stats = FocusStatsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Focus mode", isOn: $prefs.focusModeEnabled)
            } header: {
                Label("Focus Mode", systemImage: "target")
            } footer: {
                Text("When enabled, lets you start timer sessions that silence AI suggestions for distraction-free writing.")
                    .foregroundStyle(.secondary)
            }

            if prefs.focusModeEnabled {
                Section {
                    Picker("Default duration", selection: $prefs.focusDefaultDuration) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("25 min").tag(25)
                        Text("45 min").tag(45)
                    }
                    Picker("Background sound", selection: $prefs.focusSound) {
                        Text("Silence").tag("silence")
                        Text("Coffee shop").tag("coffee")
                        Text("Rain").tag("rain")
                        Text("Lo-fi").tag("lofi")
                    }
                } header: {
                    Label("Session", systemImage: "clock")
                }

                Section {
                    Toggle("Forward-only (no backspace)", isOn: $prefs.focusForwardOnly)
                    Toggle("Blindwrite (text fades as you type)", isOn: $prefs.focusBlindwrite)
                    Toggle("Kiosk mode (no escape)", isOn: $prefs.focusKiosk)
                    Stepper("Streak freeze per week: \(prefs.focusStreakFreeze)", value: $prefs.focusStreakFreeze, in: 0...7)
                } header: {
                    Label("Options", systemImage: "gearshape.2")
                }

                Section {
                    Toggle("Session complete toast", isOn: $prefs.focusCelebrateToast)
                    Toggle("Streak milestone alert", isOn: $prefs.focusCelebrateStreak)
                    Toggle("Sound effects", isOn: $prefs.focusCelebrateSound)
                } header: {
                    Label("Celebrations", systemImage: "sparkles")
                }
            }

            Section {
                statsSection
            } header: {
                Label("Focus Stats", systemImage: "chart.bar")
            }
        }
        .formStyle(.grouped)
        .task { stats.loadIfNeeded() }
    }

    @ViewBuilder
    private var statsSection: some View {
        LabeledContent("Total sessions", value: "\(stats.totalSessions)")
        LabeledContent("Total writing time",
                       value: "\(stats.totalMinutes / 60)h \(stats.totalMinutes % 60)m")
        LabeledContent("Words written in focus", value: "\(stats.totalWordsWritten)")
        LabeledContent("Current streak", value: "\(stats.currentStreak) day\(stats.currentStreak == 1 ? "" : "s")")
        LabeledContent("Longest streak", value: "\(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")")
        if let last = stats.lastSessionDate {
            LabeledContent("Last session", value: last.formatted(date: .abbreviated, time: .shortened))
        }
    }
}

/// Panel controller for FocusSessionView (NSWindow popover).
@MainActor
final class FocusSessionPanel {
    static let shared = FocusSessionPanel()
    private init() {}
    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Focus Session"
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.contentView = NSHostingView(rootView: FocusSessionView())

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
