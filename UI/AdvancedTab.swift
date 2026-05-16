import SwiftUI

struct AdvancedTab: View {
    @State private var cacheCleared = false
    @State private var serverRestarted = false

    var body: some View {
        Form {
            Section("Stato") {
                LabeledContent("Accessibilità") {
                    Label(
                        PreferencesStore.shared.isAccessibilityEnabled ? "Abilitata" : "Non abilitata",
                        systemImage: PreferencesStore.shared.isAccessibilityEnabled
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(PreferencesStore.shared.isAccessibilityEnabled ? .refineSuccess : .refineError)
                }
                LabeledContent("Bundle ID") {
                    Text(Constants.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Versione") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cache") {
                HStack {
                    Button("Svuota cache risultati") {
                        Task {
                            await ResultCache.shared.invalidateAll()
                            cacheCleared = true
                            try? await Task.sleep(for: .seconds(2))
                            cacheCleared = false
                        }
                    }
                    if cacheCleared {
                        Label("Cache svuotata", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundColor(.refineSuccess)
                    }
                }
            }

            Section("Server") {
                HStack {
                    Button("Riavvia llama-server") {
                        Task {
                            await ServerManager.shared.stop()
                            if let modelPath = ModelManager.shared.currentModelPath {
                                try? await ServerManager.shared.start(modelPath: modelPath)
                            }
                            serverRestarted = true
                            try? await Task.sleep(for: .seconds(2))
                            serverRestarted = false
                        }
                    }
                    if serverRestarted {
                        Label("Riavviato", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundColor(.refineSuccess)
                    }
                }
            }

            Section("Dati") {
                Button("Apri cartella modelli") {
                    if let dir = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first?.appendingPathComponent("RefineClone/Models") {
                        NSWorkspace.shared.open(dir)
                    }
                }
                Button("Apri cartella dati app") {
                    if let dir = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first?.appendingPathComponent("RefineClone") {
                        NSWorkspace.shared.open(dir)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
