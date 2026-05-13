import SwiftUI

struct MenuBarView: View {
    @State private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                HStack {
                    Image(systemName: "checkmark.shield")
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
                            .foregroundColor(.statusOk)
                            .frame(width: 16)
                        Text("Accessibilita: OK")
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.statusWarning)
                            .frame(width: 16)
                        Text("Accessibilita: Richiesta")
                            .font(.caption)
                    }
                }

                HStack {
                    Image(systemName: "cpu")
                        .frame(width: 16)
                    Text("Motore: \(prefs.serviceType.rawValue)")
                        .font(.caption)
                }

                let model = prefs.selectedModelID
                if !model.isEmpty {
                    HStack {
                        Image(systemName: "brain")
                            .frame(width: 16)
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
                Toggle("Controllo Automatico", isOn: $prefs.autoCheckEnabled)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("Controllo automatico")
                    .accessibilityHint("Attiva o disattiva il controllo automatico del testo")

                Button(action: { checkGrammar() }) {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("Controlla Grammatica (Cmd+Shift+E)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Controlla grammatica")
                .accessibilityHint("Cmd+Shift+E")

                Button(action: { checkFluency() }) {
                    HStack {
                        Image(systemName: "text.badge.star")
                        Text("Controlla Fluidità (Cmd+Shift+T)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Analizza tono")
                .accessibilityHint("Cmd+Shift+T")

                Button(action: { openEditor() }) {
                    HStack {
                        Image(systemName: "text.cursor")
                        Text("Apri Editor (Cmd+Shift+F)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Apri editor libero")
                .accessibilityHint("Cmd+Shift+F")

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Preferenze...")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Apri impostazioni")
                .accessibilityHint("Cmd+,")
            }

            Divider()

            Group {
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Esci")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("Esci da RefineClone")
                .accessibilityHint("Chiude l'applicazione")
            }
            .padding(.bottom, 8)
        }
        .frame(width: 250)
        .accessibilityElement(children: .contain)
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

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
