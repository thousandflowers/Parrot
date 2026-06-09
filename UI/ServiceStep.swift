import SwiftUI

// MARK: - Step 2: AI Service

struct ServiceStep: View {
    @Bindable var prefs: PreferencesStore
    @State private var openAIKey = ""
    @State private var openRouterKey = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                    Text("AI Engine")
                        .font(.title2.bold())
                    Text("Choose how Parrot will process your text.")
                        .foregroundStyle(Color.textSecondary)
                        .font(.callout)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Service")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 4)

                    Picker("Service", selection: $prefs.serviceType) {
                        Label("Apple Intelligence (built-in)", systemImage: "apple.logo")
                            .tag(ServiceType.appleIntelligence)
                        Label("Local (llama.cpp — offline)", systemImage: "memory.chip")
                            .tag(ServiceType.local)
                        Label("Local (MLX — fastest on Apple Silicon)", systemImage: "bolt.fill")
                            .tag(ServiceType.mlx)
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis.curlybraces")
                                .foregroundStyle(Color.primary)
                            Text("Ollama")
                        }
                        .tag(ServiceType.ollama)
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(Color.accentBrand)
                            Text("OpenAI / Compatibile")
                        }
                        .tag(ServiceType.remote)
                        HStack(spacing: 6) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(Color.accentPurple)
                            Text("OpenRouter")
                        }
                        .tag(ServiceType.openRouter)
                        Label("Stub (test)", systemImage: "testtube.2")
                            .tag(ServiceType.stub)
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 48)

                serviceConfig
                    .padding(.horizontal, 48)
                    .id("svc-\(prefs.serviceType.rawValue)")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.2), value: prefs.serviceType)

                Spacer(minLength: 16)
            }
        }
    }

    @ViewBuilder
    private var serviceConfig: some View {
        switch prefs.serviceType {
        case .appleIntelligence:
            VStack(alignment: .leading, spacing: 10) {
                Label("Uses Apple Intelligence — built into your Mac", systemImage: "apple.logo")
                    .foregroundStyle(Color.accentBrand)
                    .font(.callout)
                Divider()
                Text("No download needed. The model runs on-device via Apple Intelligence.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if #available(macOS 26.0, *) {
                    if !AppleIntelligenceService.shared.isAvailable {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Apple Intelligence not available", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.statusWarning)
                                .font(.caption.weight(.semibold))
                            Text(AppleIntelligenceService.shared.availabilityDescription)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .mlx:
            VStack(alignment: .leading, spacing: 10) {
                Label("MLX — Apple's ML framework, fastest local option", systemImage: "bolt.fill")
                    .foregroundStyle(Color.statusOk)
                    .font(.callout)
                Divider()
                Picker("Model", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedMLXModelID) ?? MLXLLMService.defaultModelID },
                    set: { UserDefaults.standard.set($0, forKey: Constants.UserDefaultsKey.selectedMLXModelID) }
                )) {
                    ForEach(MLXLLMService.catalog) { entry in
                        Text("\(entry.name) — \(entry.sizeLabel)").tag(entry.id)
                    }
                }
                Text("Downloaded from Hugging Face on first use, then cached. Runs 2-3× faster than llama.cpp on Apple Silicon.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .local:
            VStack(alignment: .leading, spacing: 10) {
                Label("Offline mode — no data leaves your Mac", systemImage: "lock.shield.fill")
                    .foregroundStyle(Color.statusOk)
                    .font(.callout)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("How it works")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Parrot downloads a compact AI model (~2-4 GB) that runs entirely on your Mac. Once installed, it works without internet — your text never leaves the device.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Text("Download an AI model now (optional):")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                OnboardingModelDownloader()
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .ollama:
            VStack(alignment: .leading, spacing: 8) {
                Label("Ollama", systemImage: "ellipsis.curlybraces")
                    .foregroundStyle(Color.primary)
                    .font(.callout)
                Divider()
                Text("Ollama URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("http://localhost:11434", text: $prefs.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ollama URL")
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("llama3.2", text: $prefs.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ollama model")
                Text("Make sure Ollama is running and the model is downloaded with `ollama pull <model>`.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .remote:
            VStack(alignment: .leading, spacing: 8) {
                Label("OpenAI / Compatibile", systemImage: "brain.head.profile")
                    .foregroundStyle(Color.accentBrand)
                    .font(.callout)
                Divider()
                Text("API Key OpenAI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                SecureField("sk-…", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { openAIKey = prefs.openAIAPIKey }
                    .onSubmit { prefs.openAIAPIKey = openAIKey }
                    .onDisappear { prefs.openAIAPIKey = openAIKey }
                    .accessibilityLabel("OpenAI API Key")
                Text("Base URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("https://api.openai.com/v1", text: $prefs.openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenAI base URL")
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("gpt-4o-mini", text: $prefs.openAIModel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenAI model")
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .openRouter:
            VStack(alignment: .leading, spacing: 8) {
                Label("OpenRouter", systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Color.accentPurple)
                    .font(.callout)
                Divider()
                Text("API Key OpenRouter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                SecureField("sk-or-…", text: $openRouterKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { openRouterKey = prefs.openRouterAPIKey }
                    .onSubmit { prefs.openRouterAPIKey = openRouterKey }
                    .onDisappear { prefs.openRouterAPIKey = openRouterKey }
                    .accessibilityLabel("OpenRouter API Key")
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("openai/gpt-4o-mini", text: $prefs.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenRouter model")
                Text("Find available models at openrouter.ai/models")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

        case .stub:
            Label("Test mode — no real AI", systemImage: "info.circle")
                .foregroundStyle(Color.textSecondary)
                .font(.callout)
        }
    }
}
