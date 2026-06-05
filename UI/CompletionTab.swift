import SwiftUI

/// Settings for inline predictive completion (SP1). The master toggle starts/stops the global
/// Tab interceptor so the user always has a clear off switch for the keystroke tap.
struct CompletionTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var downloadedModels: [DiscoveredModel] = []
    @State private var migrationResult: String?
    @State private var learnResult: String?

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

            if MigrationImporter.hasAnySource {
                Section {
                    Button {
                        Task {
                            let r = await MigrationImporter.importAll()
                            migrationResult = "Imported — " + r.lines.joined(separator: " · ")
                            downloadedModels = await ModelManager.shared.localModels()
                        }
                    } label: {
                        Label("Import from other apps", systemImage: "square.and.arrow.down.on.square")
                    }
                    if let migrationResult {
                        Text(migrationResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Migrate", systemImage: "arrow.right.arrow.left")
                } footer: {
                    Text("Brings over your data from Cotypist (personalization, settings, models — reused via symlink, no re-download), macOS Text Replacements, and espanso. Encrypted learning data is never touched; Wren learns its own as you go.")
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
                Divider()
                TextField("OpenAI-compatible endpoint", text: $prefs.completionOpenAIEndpoint, axis: .vertical)
                    .lineLimit(1)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                SecureField("API key (optional)", text: $prefs.completionOpenAIKey)
                    .lineLimit(1)
                    .autocorrectionDisabled()
            } header: {
                Label("Model", systemImage: "cpu")
            } footer: {
                Text("Use the main model, or pick a dedicated model for completion. Set an OpenAI-compatible endpoint (e.g. https://api.openai.com/v1) to use cloud models instead of local. Leave blank to use local models only.")
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Words per suggestion", value: "\(prefs.maxCompletionLength)")
                    Slider(value: Binding(
                        get: { Double(prefs.maxCompletionLength) },
                        set: { prefs.maxCompletionLength = Int($0.rounded()) }
                    ), in: 1...8, step: 1)
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
                Picker("Partial accept", selection: $prefs.completionPartialKeyCode) {
                    Text("Tab ↹").tag(48)
                    Text("Space").tag(49)
                    Text("Return ↵").tag(36)
                    Text("Right Arrow →").tag(124)
                }
                Picker("Full accept", selection: $prefs.completionFullKeyCode) {
                    Text("Backslash \\").tag(42)
                    Text("Tab ↹").tag(48)
                    Text("Space").tag(49)
                    Text("Return ↵").tag(36)
                    Text("Right Arrow →").tag(124)
                }
            } header: {
                Label("Accept keys", systemImage: "keyboard")
            } footer: {
                Text("Partial accept inserts the next word and re-suggests. Full accept inserts the entire suggestion. Set both to the same key to disable full accept via keyboard (\\ still works).")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
                    panel.allowedContentTypes = [.plainText, .text]
                    panel.prompt = "Learn"
                    if panel.runModal() == .OK {
                        let urls = panel.urls
                        Task {
                            let n = await CorpusLearner.learn(fromFiles: urls)
                            learnResult = n > 0 ? "Learned \(n) phrases from your writing." : "No recurring phrases found."
                        }
                    }
                } label: {
                    Label("Learn from my writing…", systemImage: "text.book.closed")
                }
                if let learnResult { Text(learnResult).font(.caption).foregroundStyle(.secondary) }
                Picker("Emoji skin tone", selection: $prefs.completionEmojiSkinTone) {
                    Text("Default").tag(0)
                    ForEach(1...5, id: \.self) { Text("Tone \($0)").tag($0) }
                }
            } header: {
                Label("Learning & Emoji", systemImage: "brain")
            } footer: {
                Text("Seed your completion memory from a folder of your own text (emails, notes). Recurring phrases come back instantly. Snippets support {{date}} {{time}} {{clipboard}} placeholders.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("e.g. Write in a friendly, concise voice.", text: $prefs.personalizationInstructions, axis: .vertical)
                    .lineLimit(2...5)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Personalization strength") {
                        Text("\(prefs.personalizationStrength, format: .percent.precision(.fractionLength(0)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $prefs.personalizationStrength, in: 0...1, step: 0.1)
                    Text("How strongly your instructions influence suggestions. 0% = base model only, 100% = full personalization.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Personalization", systemImage: "person.crop.circle")
            } footer: {
                Text("Optional note about how you write. Steers suggestions toward your voice. Higher strength = more influence.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            downloadedModels = await ModelManager.shared.localModels()
        }
    }
}
