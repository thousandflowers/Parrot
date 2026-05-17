import SwiftUI

struct OnboardingView: View {
    var onDismiss: (() -> Void)?

    @State private var step: Int = 0
    @State private var accessibilityGranted = false
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var downloadComplete = false
    @State private var downloadError: String?
    @State private var selectedModel: ModelRecommendation?
    @State private var availableModels: [ModelRecommendation] = []
    @State private var llamaServerReady = false
    @State private var downloadTask: Task<Void, Never>?

    private let steps = [
        String(localized: "onboarding.step.0"),
        String(localized: "onboarding.step.1"),
        String(localized: "onboarding.step.2"),
        String(localized: "onboarding.step.3")
    ]

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            Spacer()

            switch step {
            case 0: welcomeStep
            case 1: accessibilityStep
            case 2: modelDownloadStep
            case 3: readyStep
            default: EmptyView()
            }

            Spacer()

            navigationButtons
                .padding(.bottom, 32)
        }
        .frame(width: 440, height: 420)
        .task {
            accessibilityGranted = PreferencesStore.probeAccessibility()
            selectedModel = await ModelManager.shared.recommendedDefaultModel()
            availableModels = ModelCatalog.onboardingCandidates
            llamaServerReady = ModelManager.shared.resolvedLlamaServerURL() != nil
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<steps.count, id: \.self) { i in
                Circle()
                    .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                if i < steps.count - 1 {
                    Rectangle()
                        .fill(i < step ? Color.accentColor : Color.gray.opacity(0.2))
                        .frame(height: 2)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 40)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            Text(String(localized: "onboarding.welcome.title"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 16) {
                OnboardRow(icon: "text.badge.checkmark",
                           title: String(localized: "onboarding.welcome.feature.correction.title"),
                           detail: String(localized: "onboarding.welcome.feature.correction.detail"))
                OnboardRow(icon: "character.book.closed",
                           title: String(localized: "onboarding.welcome.feature.models.title"),
                           detail: String(localized: "onboarding.welcome.feature.models.detail"))
                OnboardRow(icon: "keyboard",
                           title: String(localized: "onboarding.welcome.feature.shortcuts.title"),
                           detail: String(localized: "onboarding.welcome.feature.shortcuts.detail"))
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Step 1: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: accessibilityGranted ? "shield.checkered" : "shield.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(accessibilityGranted ? .green : .orange)

            Text(String(localized: "onboarding.accessibility.title"))
                .font(.title2.weight(.semibold))

            Text(String(localized: "onboarding.accessibility.body"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if accessibilityGranted {
                Label(String(localized: "onboarding.accessibility.granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.weight(.medium))
            } else {
                VStack(spacing: 8) {
                    Text(String(localized: "onboarding.accessibility.instructions"))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    Button(String(localized: "onboarding.accessibility.open_settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Model Picker Button

    private var modelPickerButton: some View {
        Menu {
            ForEach(availableModels, id: \.id) { model in
                Button {
                    downloadTask?.cancel()
                    downloadTask = nil
                    isDownloading = false
                    downloadProgress = 0
                    selectedModel = model
                    downloadComplete = false
                    downloadError = nil
                } label: {
                    Text("\(model.name)  \(model.sizeLabel)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedModel?.name ?? String(localized: "onboarding.model.select_placeholder"))
                    .font(.body.weight(.medium))
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Model Download

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            Image(systemName: downloadComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(downloadComplete ? .green : .blue)

            Text(String(localized: "onboarding.model.title"))
                .font(.title2.weight(.semibold))

            modelPickerButton

            if let model = selectedModel {
                Text(model.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Text("\(model.sizeLabel) · min. \(model.ramRequired) GB RAM")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if isDownloading {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if downloadComplete {
                Label(String(localized: "onboarding.model.ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.weight(.medium))
            } else if let error = downloadError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(String(localized: "onboarding.model.retry")) {
                    downloadError = nil
                    startDownload()
                }
                .buttonStyle(.bordered)
            } else {
                Text(String(localized: "onboarding.model.download_prompt"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(String(localized: "onboarding.ready.title"))
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Label("⌘⇧E — Correggi grammatica", systemImage: "keyboard")
                Label("⌘⇧A — Correggi e applica subito", systemImage: "bolt.fill")
                Label("⌘⇧C — Writing Coach", systemImage: "graduationcap")
                Divider().padding(.vertical, 2)
                Label("Motore ibrido: regole + AI", systemImage: "cpu")
                Label("Regole personalizzate", systemImage: "list.bullet.clipboard")
                Label("90+ lingue supportate", systemImage: "globe")
                Label("Cronologia undo", systemImage: "arrow.uturn.backward")
            }
            .font(.body)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button(String(localized: "onboarding.nav.back")) {
                    step -= 1
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            if step < 3 {
                let canAdvance = step != 1 || accessibilityGranted
                Button(step == 2
                    ? (isDownloading
                        ? String(localized: "onboarding.nav.downloading")
                        : (downloadComplete
                            ? String(localized: "onboarding.nav.next")
                            : String(localized: "onboarding.nav.download")))
                    : String(localized: "onboarding.nav.next")) {
                    if step == 2 && !isDownloading && !downloadComplete {
                        startDownload()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAdvance || (step == 2 && isDownloading))
            } else {
                Button(String(localized: "onboarding.nav.start")) {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Download

    private func startDownload() {
        guard let model = selectedModel else { return }
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        downloadTask = Task {
            do {
                let stream = await ModelManager.shared.downloadModelWithProgress(from: model.url)
                for try await progress in stream {
                    if progress > 0 {
                        await MainActor.run { downloadProgress = progress }
                    }
                }
                await MainActor.run {
                    isDownloading = false
                    downloadComplete = true
                    UserDefaults.standard.set(model.id, forKey: Constants.UserDefaultsKey.selectedModelID)
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadError = "Download fallito: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct OnboardRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}
