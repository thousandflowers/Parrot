import SwiftUI

/// Settings for inline predictive completion (SP1). The master toggle starts/stops the global
/// Tab interceptor so the user always has a clear off switch for the keystroke tap.
struct CompletionTab: View {
    @Bindable var prefs: PreferencesStore

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
    }
}
