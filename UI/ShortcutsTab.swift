import SwiftUI
import Carbon

struct ShortcutsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        Form {
            Section {
                ShortcutRow(label: "Grammar correction",
                            shortcut: $prefs.shortcutGrammar,
                            defaultValue: .grammarDefault)
                ShortcutRow(label: "Fluency correction",
                            shortcut: $prefs.shortcutFluency,
                            defaultValue: .fluencyDefault)
                ShortcutRow(label: "Translate",
                            shortcut: $prefs.shortcutTranslate,
                            defaultValue: .translateDefault)
                ShortcutRow(label: "Writing coach",
                            shortcut: $prefs.shortcutCoach,
                            defaultValue: .coachDefault)
                ShortcutRow(label: "De-slop (remove AI-sounding patterns)",
                            shortcut: $prefs.shortcutDeSlop,
                            defaultValue: .deSlopDefault)
                ShortcutRow(label: "Optimize for AI prompt",
                            shortcut: $prefs.shortcutAIPrompt,
                            defaultValue: .aiPromptDefault)
            } header: {
                Text("Analysis")
            }

            Section {
                ShortcutRow(label: "Apply correction (with panel)",
                            shortcut: $prefs.shortcutReplace,
                            defaultValue: .replaceDefault)
                ShortcutRow(label: "Apply correction (silent)",
                            shortcut: $prefs.shortcutApplyDirect,
                            defaultValue: .applyDirectDefault)
                ShortcutRow(label: "Apply all inline annotations",
                            shortcut: $prefs.shortcutApplyAll,
                            defaultValue: .applyAllDefault)
            } header: {
                Text("Application")
            } footer: {
                Text("\"Apply all inline annotations\" applies all visible underlined corrections in the current text at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ShortcutRow(label: "Open floating editor",
                            shortcut: $prefs.shortcutEditor,
                            defaultValue: .editorDefault)
            } header: {
                Text("Tools")
            } footer: {
                Text("Requires at least ⌘, ⌃ or ⌥. Active globally system-wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onChange(of: allShortcutsHash) { _, _ in GlobalHotkeyManager.current?.updateHotkeys() }
    }

    private var allShortcutsHash: Int {
        var hasher = Hasher()
        hasher.combine(prefs.shortcutGrammar)
        hasher.combine(prefs.shortcutFluency)
        hasher.combine(prefs.shortcutTranslate)
        hasher.combine(prefs.shortcutCoach)
        hasher.combine(prefs.shortcutReplace)
        hasher.combine(prefs.shortcutApplyDirect)
        hasher.combine(prefs.shortcutApplyAll)
        hasher.combine(prefs.shortcutEditor)
        hasher.combine(prefs.shortcutGrammarFluency)
        hasher.combine(prefs.shortcutDeSlop)
        hasher.combine(prefs.shortcutAIPrompt)
        return hasher.finalize()
    }
}

// MARK: - Row

private struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: ShortcutConfig
    let defaultValue: ShortcutConfig

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { shortcut.isEnabled },
                set: { shortcut.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Text(label)
                .foregroundStyle(shortcut.isEnabled ? .primary : .secondary)

            Spacer()

            if shortcut.isEnabled {
                ShortcutRecorder(shortcut: $shortcut, defaultValue: defaultValue, label: label)
            } else {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 90, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                    )
            }
        }
    }
}

// MARK: - Recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: ShortcutConfig
    let defaultValue: ShortcutConfig
    let label: String

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pulsePhase = 0.0
    @State private var pulseTimer = Timer.publish(every: 0.15, on: .main, in: .default).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Text(isRecording ? "Press a shortcut…" : shortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 90, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                )
                .overlay(
                    isRecording ? RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.3 + 0.3 * sin(pulsePhase)), lineWidth: 2)
                        : nil
                )
                .onReceive(pulseTimer) { _ in
                    guard isRecording else { return }
                    pulsePhase += 0.4
                }

            Button(isRecording ? "Cancel" : "Edit") {
                isRecording ? cancelRecording() : startRecording()
            }
            .controlSize(.small)
            .accessibilityLabel(isRecording ? "Cancel shortcut recording for \(label)" : "Edit shortcut for \(label)")

            Button("Reset") {
                cancelRecording()
                shortcut = defaultValue
            }
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reset shortcut for \(label)")
        }
        .onChange(of: isRecording) { _, recording in
            if recording { startCapture() } else { stopCapture() }
        }
        .onDisappear { cancelRecording() }
    }

    private func startRecording() { isRecording = true }
    private func cancelRecording() { isRecording = false }

    private func startCapture() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
                return nil
            }
            if let cfg = ShortcutConfig.fromNSEvent(event) {
                shortcut = cfg
                isRecording = false
                return nil
            }
            return event
        }
    }

    private func stopCapture() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

#Preview {
    ShortcutsTab(prefs: PreferencesStore.shared)
}
