import SwiftUI

struct MenuBarView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var isRealtimeEnabled = false

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
                Toggle("Controllo in Tempo Reale", isOn: $isRealtimeEnabled)
                    .padding(.horizontal, 12)

                Button(action: { checkGrammar() }) {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("Controlla Grammatica (Cmd+Shift+E)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { checkFluency() }) {
                    HStack {
                        Image(systemName: "text.badge.star")
                        Text("Controlla Fluidità (Cmd+Shift+T)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { openEditor() }) {
                    HStack {
                        Image(systemName: "text.cursor")
                        Text("Apri Editor (Cmd+Shift+F)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Preferenze...")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Group {
                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
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
        .onChange(of: isRealtimeEnabled) { _, newValue in
            prefs.realtimeEnabled = newValue
        }
        .onAppear {
            isRealtimeEnabled = prefs.realtimeEnabled
        }
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
                Toggle("Controllo in Tempo Reale", isOn: $isRealtimeEnabled)
                    .padding(.horizontal, 12)

                Button(action: { checkGrammar() }) {
                    HStack {
                        Image(systemName: "text.badge.checkmark")
                        Text("Controlla Grammatica (Cmd+Shift+E)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { checkFluency() }) {
                    HStack {
                        Image(systemName: "text.badge.star")
                        Text("Controlla Fluidità (Cmd+Shift+T)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button(action: { openEditor() }) {
                    HStack {
                        Image(systemName: "text.cursor")
                        Text("Apri Editor (Cmd+Shift+F)")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Preferenze...")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Group {
                Button(action: { NSApp.terminate(nil) }) {
                    HStack {
                        Image(systemName: "power")
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
        .onChange(of: isRealtimeEnabled) { _, newValue in
            prefs.realtimeEnabled = newValue
        }
        .onAppear {
            isRealtimeEnabled = prefs.realtimeEnabled
        }
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
