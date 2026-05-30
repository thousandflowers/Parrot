import SwiftUI

/// Settings for inline predictive completion (SP1). The master toggle starts/stops the global
/// Tab interceptor so the user always has a clear off switch for the keystroke tap.
struct CompletionTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var downloadedModels: [DiscoveredModel] = []
    @State private var migrationResult: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable inline completion", isOn: Binding(
                    get: { prefs.inlineCompletionEnabled },
                    set: { newValue in
                        prefs.inlineCompletionEnabled = newValue
                        if newValue {
                            TabInterceptor.shared.start()
                            Task { await RealtimeMonitor.shared.start() }
                        } else {
                            TabInterceptor.shared.stop()
                            CompletionController.shared.dismiss()
                        }
                    }
                ))
            } header: {
                Label("Inline completion", systemImage: "text.append")
            } footer: {
                Text("As you type in any app, Parrot suggests a continuation in grey. Press Tab to accept. On-device.")
                    .foregroundStyle(.secondary)
            }

            if CotypistMigration.isAvailable {
                Section {
                    Button {
                        let imported = CotypistMigration.migrate()
                        migrationResult = imported.isEmpty ? "Nothing to import." : "Imported: " + imported.joined(separator: ", ") + "."
                        Task { downloadedModels = await ModelManager.shared.localModels() }
                    } label: {
                        Label("Import from Cotypist", systemImage: "square.and.arrow.down.on.square")
                    }
                    if let migrationResult {
                        Text(migrationResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Migrate", systemImage: "arrow.right.arrow.left")
                } footer: {
                    Text("Brings over your personalization and reuses Cotypist's downloaded models (instant, no re-download). Your typing history stays in Cotypist — Wren learns its own as you go.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Completion model", selection: $prefs.completionModelID) {
                    Text("Same as correction model").tag("")
                    ForEach(downloadedModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            } header: {
                Label("Model", systemImage: "cpu")
            } footer: {
                Text("Use the main model, or pick a dedicated model for completion. A small base model gives faster, more on-topic suggestions; a different model runs on its own background server (more RAM).")
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $prefs.maxCompletionLength, in: 1...30) {
                    LabeledContent("Max words", value: "\(prefs.maxCompletionLength)")
                }
                Stepper(value: $prefs.completionDebounceMs, in: 120...1500, step: 20) {
                    LabeledContent("Typing pause", value: "\(prefs.completionDebounceMs) ms")
                }
            } header: {
                Label("Behavior", systemImage: "slider.horizontal.3")
            } footer: {
                Text("How long the suggestion can be, and how long to wait after you stop typing before suggesting.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use screen context", isOn: Binding(
                    get: { prefs.completionUseScreenContext },
                    set: { newValue in
                        prefs.completionUseScreenContext = newValue
                        if newValue { ScreenContextProvider.requestPermission() }
                    }
                ))
                Toggle("Use clipboard context", isOn: $prefs.completionUseClipboardContext)
            } header: {
                Label("Context", systemImage: "rectangle.dashed.and.paperclip")
            } footer: {
                Text("Screen context reads on-screen text (the conversation/email you're replying to) via on-device OCR (throttled, needs Screen Recording). Clipboard context adds your copied text. Both ground suggestions so they fit.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("e.g. Write in a friendly, concise voice.", text: $prefs.completionUserPrompt, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Label("Personalization", systemImage: "person.crop.circle")
            } footer: {
                Text("Optional note about how you write. Used to steer suggestions toward your voice.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            downloadedModels = await ModelManager.shared.localModels()
        }
    }
}
