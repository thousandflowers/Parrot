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
                            .foregroundColor(.green)
                            .frame(width: 16)
                        Text("Accessibilita: OK")
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
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
                    .accessibilityHint("Controlla il testo automaticamente mentre scrivi")

                Button(action: { checkGrammar() }) {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("Controlla Grammatica (Cmd+Shift+E)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Controlla Grammatica")
                .accessibilityHint("Correggi errori grammaticali nel testo selezionato")

                Button(action: { checkFluency() }) {
                    HStack {
                        Image(systemName: "text.badge.star")
                        Text("Controlla Fluidità (Cmd+Shift+T)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Controlla Fluidità")
                .accessibilityHint("Migliora la fluidità del testo selezionato")

                Button(action: { openEditor() }) {
                    HStack {
                        Image(systemName: "text.cursor")
                        Text("Apri Editor (Cmd+Shift+F)")
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .accessibilityLabel("Apri Editor")

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
            }

            Divider()

            Group {
                HStack {
                    Text("Lingua:")
                        .font(.caption)
                    Picker("", selection: $prefs.language) {
                        Text("🇮🇹 IT").tag("it")
                        Text("🇬🇧 EN").tag("en-US")
                        Text("🇪🇸 ES").tag("es")
                        Text("🇫🇷 FR").tag("fr")
                        Text("🇩🇪 DE").tag("de")
                    }
                    .labelsHidden()
                    .frame(width: 70)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

                HStack {
                    Text("Stile:")
                        .font(.caption)
                    Picker("", selection: $prefs.style) {
                        Text("Equilibrato").tag("equilibrato")
                        Text("Formale").tag("formale")
                        Text("Informale").tag("informale")
                    }
                    .labelsHidden()
                    .frame(width: 95)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
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

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
