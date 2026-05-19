import SwiftUI

struct GeneralTab: View {
    @Bindable var prefs: PreferencesStore
    var serverIsRunning: Bool

    var body: some View {
        Form {
            Section {
                Picker("Service", selection: $prefs.serviceType) {
                    Text("Local (llama.cpp)").tag(ServiceType.local)
                    Text("Ollama").tag(ServiceType.ollama)
                    Text("OpenAI / Compatible").tag(ServiceType.remote)
                    Text("OpenRouter").tag(ServiceType.openRouter)
                    Text("Stub (test)").tag(ServiceType.stub)
                }

                if prefs.serviceType == .remote {
                    OpenAIKeyField(prefs: prefs)
                    TextField("Base URL", text: $prefs.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $prefs.openAIModel)
                        .textFieldStyle(.roundedBorder)
                }

                if prefs.serviceType == .ollama {
                    TextField("Ollama URL", text: $prefs.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $prefs.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                }

                if prefs.serviceType == .openRouter {
                    OpenRouterKeyField(prefs: prefs)
                    TextField("Model (e.g. openai/gpt-4o-mini)", text: $prefs.openRouterModel)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Label("AI Engine", systemImage: "cpu")
            }

            Section {
                Toggle("Auto-check", isOn: $prefs.autoCheckEnabled)
                Toggle("Real-time check", isOn: $prefs.realtimeEnabled)
            } header: {
                Label("Behavior", systemImage: "bolt")
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(serverIsRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serverIsRunning ? "llama-server running" : "llama-server not running")
                        .font(.callout)
                }
                if prefs.serviceType == .local && !serverIsRunning {
                    Text("The local server is not running. Check the configuration in the Models tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Status", systemImage: "antenna.radiowaves.left.and.right")
            }

            if prefs.serviceType == .local {
                LlamaInstallerSection()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - llama-server Installer

private struct LlamaInstallerSection: View {
    private var installer: LlamaInstaller { LlamaInstaller.shared }

    var body: some View {
        switch installer.phase {
        case .unknown:
            EmptyView()
                .onAppear { installer.checkAvailability() }

        case .available:
            EmptyView()

        case .unavailable:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("llama-server not found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout.weight(.medium))
                    Text("The local AI engine is not installed. Parrot can install it automatically via Homebrew, or download a prebuilt binary from GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Install llama-server") { installer.install() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }

        case .installing(let progress, let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.callout)
                    if progress < 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                    Text("Do not close the app while installing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }

        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Installation failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout.weight(.medium))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Try Again") { installer.install() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Install Homebrew first…") {
                            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Label("Engine Setup", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}

// MARK: - Key Fields

private struct OpenAIKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenAI", text: $localKey)
            .onAppear { localKey = prefs.openAIAPIKey }
            .onSubmit { prefs.openAIAPIKey = localKey }
            .onDisappear { prefs.openAIAPIKey = localKey }
    }
}

private struct OpenRouterKeyField: View {
    let prefs: PreferencesStore
    @State private var localKey: String = ""

    var body: some View {
        SecureField("API Key OpenRouter", text: $localKey)
            .onAppear { localKey = prefs.openRouterAPIKey }
            .onSubmit { prefs.openRouterAPIKey = localKey }
            .onDisappear { prefs.openRouterAPIKey = localKey }
    }
}
