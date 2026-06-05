import SwiftUI
import AppKit

struct AdvancedTab: View {
    @Bindable var prefs: PreferencesStore
    @State private var hfToken: String = ""
    @State private var savedHFToken: String = ""
    @State private var tokenSaved = false
    @State private var cacheClearedMessage = false
    @AppStorage(Constants.UserDefaultsKey.lightweightMode) private var lightweightMode = false
    @State private var compatResult: String?
    @State private var compatChecking = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $prefs.language) {
                    ForEach(supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            } header: {
                Label("Language", systemImage: "globe")
            } footer: {
                Text("Language used for completion, grammar, fluency, and all prompts. Defaults to your macOS locale. Change only if you write in a different language.")
            }

            if AppMode.current.showsCompletion {
                Section {
                    Text("Focus a text field in the app you want to check, then click below. Wren reports whether it can read that field for context-aware completion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(compatChecking ? "Checking…" : "Check last focused app") {
                        checkCompatibility()
                    }
                    .disabled(compatChecking)
                    if let r = compatResult {
                        Text(r)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                } header: {
                    Label("App compatibility", systemImage: "checklist")
                }
            }

            Section {
                HStack {
                    SecureField("HF token (optional, for faster downloads)", text: $hfToken)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("HuggingFace token")
                    Button("Save") { saveHFToken() }
                        .disabled(hfToken == savedHFToken)
                        .accessibilityLabel("Save")
                }
                if tokenSaved {
                    Label("Token saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.statusOk)
                }
            } header: {
                Label("HuggingFace", systemImage: "arrow.down.circle")
            } footer: {
                Text("Without token: ~500 KB/s · With token: up to 50 MB/s. Create a token at huggingface.co/settings/tokens (type: Read).")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Lightweight mode (fewer threads, lower CPU usage)", isOn: $lightweightMode)
                    .accessibilityLabel("Lightweight mode")

                Button("Clear response cache") {
                    Task {
                        await CorrectionCache.shared.invalidateAll()
                        cacheClearedMessage = true
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        cacheClearedMessage = false
                    }
                }

                if cacheClearedMessage {
                    Label("Cache cleared", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.statusOk)
                }

                Button("Show initial setup…") {
                    OnboardingController.shared.show()
                }
            } header: {
                Label("Advanced", systemImage: "gearshape.2")
            }

            Section {
                LabeledContent("Accessibility") {
                    Text(PreferencesStore.shared.isAccessibilityEnabled ? "Enabled" : "Not enabled")
                        .foregroundStyle(PreferencesStore.shared.isAccessibilityEnabled ? Color.statusOk : Color.statusWarning)
                }
                LabeledContent("Bundle ID") {
                    Text(Constants.bundleID)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Label("Diagnostics", systemImage: "wrench.and.screwdriver")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What data leaves your device?")
                        .font(.callout.weight(.medium))
                    Text("The text you correct is sent only to the AI service you select. **Local (llama.cpp)** and **Ollama** process everything on-device — no data leaves your Mac. **OpenAI** and **OpenRouter** send your text to their cloud APIs; their privacy policies apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("API keys are stored in your macOS Keychain, never in preferences files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("OpenAI Privacy Policy") {
                            guard let url = URL(string: "https://openai.com/policies/privacy-policy") else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .font(.caption)
                        Button("OpenRouter Privacy Policy") {
                            guard let url = URL(string: "https://openrouter.ai/privacy") else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Privacy & Data", systemImage: "hand.raised")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadHFToken() }
    }

    private let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("it", "Italiano"),
        ("fr", "Français"),
        ("es", "Español"),
        ("de", "Deutsch"),
        ("pt", "Português"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("sv", "Svenska"),
        ("da", "Dansk"),
        ("no", "Norsk"),
        ("fi", "Suomi"),
        ("ru", "Русский"),
        ("bg", "Български"),
        ("cs", "Čeština"),
        ("uk", "Українська"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("ko", "한국어"),
        ("ar", "العربية"),
        ("he", "עברית"),
    ]

    private func loadHFToken() {
        let token = (try? KeychainService.shared.load(for: "hftoken")) ?? ""
        hfToken = token
        savedHFToken = token
    }

    private func saveHFToken() {
        do {
            if hfToken.isEmpty {
                try KeychainService.shared.delete(for: "hftoken")
            } else {
                try KeychainService.shared.save(key: hfToken, for: "hftoken")
            }
            savedHFToken = hfToken
            tokenSaved = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                tokenSaved = false
            }
        } catch {
            // Keychain write failed — no confirmation shown
        }
    }

    /// Probes the last-focused (non-Wren) app for inline-completion compatibility and shows the
    /// verdict, so users can build/verify the "Works in" matrix themselves.
    private func checkCompatibility() {
        compatChecking = true
        compatResult = nil
        Task {
            let pid = await AccessibilityBridge.shared.lastKnownFrontAppPID()
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "the focused app"
            let verdict: AppCompatibility
            if pid == 0 {
                verdict = .noFocus
            } else {
                verdict = await CompatibilityProbe.probe(
                    pid: pid,
                    contextProvider: { await AccessibilityBridge.shared.completionContext(pid: $0) },
                    hasFocusedField: { _ in false }
                )
            }
            await MainActor.run {
                compatResult = "\(appName): \(verdict.verdict)"
                compatChecking = false
            }
        }
    }
}

#Preview {
    AdvancedTab(prefs: PreferencesStore.shared)
}
