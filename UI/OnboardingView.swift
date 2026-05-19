import SwiftUI
import ApplicationServices

// MARK: - Controller

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?
    private static let completedKey = "hasCompletedOnboarding"

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        show()
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Initial Setup — Refine"
        w.center()
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("OnboardingWindow")

        w.contentView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.window?.close()
            self?.window = nil
        }))

        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root View

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var prefs = PreferencesStore.shared

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: step)

            Divider()
            bottomBar
        }
        .frame(width: 620, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: WelcomeStep()
        case 1: AccessibilityStep()
        case 2: ServiceStep(prefs: prefs)
        case 3: LanguageStyleStep()
        case 4: ShortcutsStep()
        default: ReadyStep(prefs: prefs)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }

            Spacer()

            stepDots

            Spacer()

            Button("Skip") { onComplete() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)

            if step < totalSteps - 1 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                Button("Start using Refine") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("Welcome to Refine")
                    .font(.largeTitle.bold())

                Text("Your writing assistant for Mac")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                FeatureRow(icon: "text.badge.checkmark", color: .green,
                           title: "Grammar anywhere",
                           subtitle: "Select text in any app and press ⌘⇧E")
                FeatureRow(icon: "sparkles", color: .purple,
                           title: "Improve fluency",
                           subtitle: "Make your text more natural and readable")
                FeatureRow(icon: "lock.shield", color: .blue,
                           title: "Completely private",
                           subtitle: "Everything runs locally — no data leaves your Mac")
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .padding()
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Step 1: Accessibility

private struct AccessibilityStep: View {
    @State private var isGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: isGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isGranted ? Color.green : Color.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            .animation(.spring(response: 0.4), value: isGranted)

            VStack(spacing: 10) {
                Text(isGranted ? "Permissions granted!" : "Accessibility Permissions")
                    .font(.title2.bold())

                Text(isGranted
                    ? "Refine can now read and modify text in other applications."
                    : "Refine needs access to text in other applications to correct grammar."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 48)
            }

            if !isGranted {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("System Settings → Privacy & Security → Accessibility → add Refine")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }
            }

            Spacer()
        }
        .padding()
        .task {
            while !isGranted {
                try? await Task.sleep(for: .milliseconds(600))
                isGranted = AXIsProcessTrusted()
            }
        }
    }
}

// MARK: - Step 2: AI Service

private struct ServiceStep: View {
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
                    Text("Choose how Refine will process your text.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Service")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    Picker("Service", selection: $prefs.serviceType) {
                        Label("Local (llama.cpp — offline)", systemImage: "lock.shield")
                            .tag(ServiceType.local)
                        Label("Ollama", systemImage: "server.rack")
                            .tag(ServiceType.ollama)
                        Label("OpenAI / Compatibile", systemImage: "cloud")
                            .tag(ServiceType.remote)
                        Label("OpenRouter", systemImage: "arrow.triangle.swap")
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

                Spacer(minLength: 16)
            }
        }
    }

    @ViewBuilder
    private var serviceConfig: some View {
        switch prefs.serviceType {
        case .local:
            VStack(alignment: .leading, spacing: 10) {
                Label("Offline mode — no data leaves your Mac", systemImage: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                Divider()
                Text("Download an AI model now (optional):")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                OnboardingModelDownloader()
            }
            .padding(12)
            .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

        case .ollama:
            VStack(alignment: .leading, spacing: 8) {
                Text("Ollama URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("http://localhost:11434", text: $prefs.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("llama3.2", text: $prefs.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                Text("Make sure Ollama is running and the model is downloaded with `ollama pull <model>`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .remote:
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key OpenAI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("sk-…", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { openAIKey = prefs.openAIAPIKey }
                    .onSubmit { prefs.openAIAPIKey = openAIKey }
                    .onDisappear { prefs.openAIAPIKey = openAIKey }
                Text("Base URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://api.openai.com/v1", text: $prefs.openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("gpt-4o-mini", text: $prefs.openAIModel)
                    .textFieldStyle(.roundedBorder)
            }

        case .openRouter:
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key OpenRouter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("sk-or-…", text: $openRouterKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { openRouterKey = prefs.openRouterAPIKey }
                    .onSubmit { prefs.openRouterAPIKey = openRouterKey }
                    .onDisappear { prefs.openRouterAPIKey = openRouterKey }
                Text("Model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("openai/gpt-4o-mini", text: $prefs.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                Text("Find available models at openrouter.ai/models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .stub:
            Label("Test mode — no real AI", systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}

// MARK: - Step 3: Smart Detection

private struct LanguageStyleStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("Smart Auto-Detection")
                    .font(.title2.bold())
                Text("No configuration needed.")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            VStack(spacing: 12) {
                FeatureRow(icon: "globe", color: .blue,
                           title: "Language",
                           subtitle: "Detected automatically from the selected text using Apple's NLP framework")
                FeatureRow(icon: "text.alignleft", color: .purple,
                           title: "Writing style",
                           subtitle: "Inferred from context — formal email, casual chat, technical docs, academic writing")
                FeatureRow(icon: "apps.iphone", color: .green,
                           title: "App-aware",
                           subtitle: "Adapts to Xcode, Slack, Mail, Pages and 15+ other apps automatically")
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 4: Shortcuts

private struct ShortcutsStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())
                Text("Active system-wide, in any application.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(spacing: 2) {
                ShortcutRow(keys: "⌘⇧E", action: "Check Grammar",
                            detail: "Corrects the selected text")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧T", action: "Check Fluency",
                            detail: "Makes text more natural and readable")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧F", action: "Open floating editor",
                            detail: "Dedicated editor with original/corrected comparison")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧Y", action: "Translate",
                            detail: "Translates the selected text")
            }
            .padding(.horizontal, 48)

            Text("All shortcuts are customizable in Settings → Shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Text(keys)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .frame(width: 72, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(action)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 5: Ready

private struct ReadyStep: View {
    let prefs: PreferencesStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("All set!")
                    .font(.largeTitle.bold())
                Text("Refine is configured and ready to use.")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 10) {
                ReadyCheckRow(
                    icon: "checkmark.circle.fill", color: .green,
                    text: "AI engine: \(prefs.serviceType.rawValue.capitalized)"
                )
                ReadyCheckRow(
                    icon: "checkmark.circle.fill", color: .green,
                    text: "Language & style: auto-detected"
                )
                ReadyCheckRow(
                    icon: "checkmark.circle.fill", color: .green,
                    text: "Global shortcuts active"
                )
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 60)

            Text("Select text in any app and press ⌘⇧E to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }


}

private struct ReadyCheckRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
            Spacer()
        }
    }
}

// MARK: - Inline Model Downloader (used in onboarding)

private struct OnboardingModelDownloader: View {
    @State private var models: [ModelRecommendation] = []
    @State private var selectedIndex = 0
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var isComplete = false
    @State private var errorMessage: String?
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if models.isEmpty {
                ProgressView().scaleEffect(0.7).frame(maxWidth: .infinity, alignment: .leading)
            } else if isComplete {
                Label("Model ready to use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $selectedIndex) {
                        ForEach(Array(models.enumerated()), id: \.offset) { idx, model in
                            Text(model.name + " — " + model.reason).tag(idx)
                        }
                    }
                    .labelsHidden()
                    .disabled(isDownloading)

                    if isDownloading {
                        ProgressView(value: progress)
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            downloadTask?.cancel()
                            downloadTask = nil
                            isDownloading = false
                            progress = 0
                            statusMessage = ""
                        }
                        .controlSize(.small)
                    } else {
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Button("Download now") { startDownload() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Text("or download later from Settings → Models")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            models = await ModelManager.shared.recommendedModels()
        }
    }

    private func startDownload() {
        guard !models.isEmpty else { return }
        let model = models[min(selectedIndex, models.count - 1)]
        isDownloading = true
        progress = 0
        statusMessage = "Starting download…"
        errorMessage = nil
        downloadTask = Task {
            do {
                let stream = ModelManager.shared.downloadModelWithProgress(from: model.url, expectedSHA256: model.expectedSHA256)
                for try await p in stream {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        switch p {
                        case .downloading(let f): progress = f; statusMessage = "Downloading \(Int(f * 100))%"
                        case .verifying(let f): progress = f; statusMessage = "Verifying \(Int(f * 100))%"
                        case .complete: progress = 1.0; statusMessage = "Complete"
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    PreferencesStore.shared.selectedModelID = model.id
                    PreferencesStore.shared.serviceType = .local
                    isDownloading = false
                    isComplete = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
