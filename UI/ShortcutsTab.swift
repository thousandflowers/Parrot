import SwiftUI
import Carbon

struct ShortcutsTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        Form {
            Section {
                ShortcutRow(label: "Correzione grammatica",
                            shortcut: $prefs.shortcutGrammar,
                            defaultValue: .grammarDefault)
                ShortcutRow(label: "Correzione fluidità",
                            shortcut: $prefs.shortcutFluency,
                            defaultValue: .fluencyDefault)
                ShortcutRow(label: "Apri editor flottante",
                            shortcut: $prefs.shortcutEditor,
                            defaultValue: .editorDefault)
                ShortcutRow(label: "Sostituisci automaticamente",
                            shortcut: $prefs.shortcutReplace,
                            defaultValue: .replaceDefault)
                ShortcutRow(label: "Traduci",
                            shortcut: $prefs.shortcutTranslate,
                            defaultValue: .translateDefault)
            } header: {
                Text("Scorciatoie da tastiera")
            } footer: {
                Text("Richiede almeno ⌘, ⌃ o ⌥. Attive globalmente su tutto il sistema.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: ShortcutConfig
    let defaultValue: ShortcutConfig

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ShortcutRecorder(shortcut: $shortcut, defaultValue: defaultValue, label: label)
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
            Text(isRecording ? "Premi una scorciatoia…" : shortcut.displayString)
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

            Button(isRecording ? "Annulla" : "Modifica") {
                isRecording ? cancelRecording() : startRecording()
            }
            .controlSize(.small)
            .accessibilityLabel(isRecording ? "Annulla registrazione scorciatoia per \(label)" : "Modifica scorciatoia per \(label)")

            Button("Reset") {
                cancelRecording()
                shortcut = defaultValue
            }
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reset scorciatoia per \(label)")
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
