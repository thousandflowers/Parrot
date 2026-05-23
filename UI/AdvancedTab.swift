import SwiftUI

struct AdvancedTab: View {
    @State private var hfToken: String = ""
    @State private var savedHFToken: String = ""
    @State private var tokenSaved = false
    @State private var cacheClearedMessage = false
    @AppStorage(Constants.UserDefaultsKey.lightweightMode) private var lightweightMode = false

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("HF token (optional, for faster downloads)", text: $hfToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { saveHFToken() }
                        .disabled(hfToken == savedHFToken)
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
                            NSWorkspace.shared.open(URL(string: "https://openai.com/policies/privacy-policy")!)
                        }
                        .font(.caption)
                        Button("OpenRouter Privacy Policy") {
                            NSWorkspace.shared.open(URL(string: "https://openrouter.ai/privacy")!)
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
}

#Preview {
    AdvancedTab()
}
