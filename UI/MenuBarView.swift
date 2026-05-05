import SwiftUI

struct MenuBarView: View {
    private let preferences = PreferencesStore.shared
    @State private var isAutoCheckEnabled = false

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
                if preferences.isAccessibilityEnabled {
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
                    Text("Motore: \(preferences.serviceType.rawValue)")
                        .font(.caption)
                }

                let model = preferences.selectedModelID
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
                Toggle("Controllo Automatico", isOn: $isAutoCheckEnabled)
                    .padding(.horizontal, 12)

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
        .onChange(of: isAutoCheckEnabled) { _, newValue in
            preferences.autoCheckEnabled = newValue
        }
        .onAppear {
            isAutoCheckEnabled = preferences.autoCheckEnabled
        }
    }

    private func openEditor() {
        FloatingEditorController.shared.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}
