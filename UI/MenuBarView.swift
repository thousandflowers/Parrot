import SwiftUI

struct MenuBarView: View {
    @State private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .accessibilityHidden(true)
                    Text("RefineClone")
                        .font(.headline)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            Divider()

            Group {
                if prefs.isAccessibilityEnabled {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.refineSuccess)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text("Accessibilità: OK")
                            .font(.caption)
                    }
                } else {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.refineWarning)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text("Accessibilità: Riabilita in Impostazioni →")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Image(systemName: "cpu")
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Motore: \(prefs.serviceType.rawValue)")
                        .font(.caption)
                }

                let model = prefs.selectedModelID
                if !model.isEmpty {
                    HStack {
                        Image(systemName: "brain")
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text("Modello: \(model)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Divider()

            Group {
                Toggle("Controllo in Tempo Reale", isOn: Bindable(prefs).realtimeEnabled)
                    .padding(.horizontal, 12)

                Button(action: { checkGrammar() }) {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                            .accessibilityHidden(true)
                        Text("Controlla Grammatica (Cmd+Shift+E)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { checkFluency() }) {
                    HStack {
                        Image(systemName: "text.badge.star")
                            .accessibilityHidden(true)
                        Text("Controlla Fluidità (Cmd+Shift+T)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { openEditor() }) {
                    HStack {
                        Image(systemName: "text.cursor")
                            .accessibilityHidden(true)
                        Text("Apri Editor (Cmd+Shift+F)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { TextCheckCoordinator.shared.checkAndReplace() }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .accessibilityHidden(true)
                        Text("Sostituisci (Cmd+Shift+R)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { TextCheckCoordinator.shared.checkTranslation() }) {
                    HStack {
                        Image(systemName: "translate")
                            .accessibilityHidden(true)
                        Text("Traduci (Cmd+Shift+Y)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { TextCheckCoordinator.shared.checkCoach() }) {
                    HStack {
                        Image(systemName: "graduationcap")
                            .accessibilityHidden(true)
                        Text("Writing Coach (Cmd+Shift+C)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                            .accessibilityHidden(true)
                        Text("Preferenze...")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Group {
                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                            .accessibilityHidden(true)
                        Text("Esci")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 250)
    }

    private func checkGrammar() {
        let pid = resolveFrontmostPID()
        if pid > 0 {
            TextCheckCoordinator.shared.checkSelectedText(fromPID: pid)
        } else {
            TextCheckCoordinator.shared.checkSelectedText()
        }
    }

    private func checkFluency() {
        let pid = resolveFrontmostPID()
        if pid > 0 {
            TextCheckCoordinator.shared.checkFluency(fromPID: pid)
        } else {
            TextCheckCoordinator.shared.checkFluency()
        }
    }

    private func resolveFrontmostPID() -> pid_t {
        let tracked = AccessibilityBridge.lastKnownFrontAppPID
        if tracked > 0 { return tracked }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return 0
        }
        return frontApp.processIdentifier
    }

    private func openEditor() {
        FloatingEditorController.shared.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}
