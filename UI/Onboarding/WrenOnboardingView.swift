import SwiftUI
import AppKit
import IOKit.hid

struct WrenOnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var coordinator: ModelDownloadCoordinator?
    @State private var recommended: ModelRecommendation?
    private let totalSteps = 5

    var body: some View {
        OnboardingScaffold(
            step: step,
            totalSteps: totalSteps,
            finalActionTitle: "Start using Wren",
            onBack: { step -= 1 },
            onNext: { step += 1 },
            onSkip: onComplete,
            onFinish: onComplete,
            content: { stepContent },
            footerAccessory: { downloadBar }
        )
        .task { await prepareDownload() }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: WrenWelcomeStep(recommended: recommended)
        case 1: InputMonitoringStep()
        case 2: TonePracticeView(phrases: TonePhrases.rotating(count: 3, seed: 0))
        case 3: WrenScreenContextStep()
        default: WrenReadyStep(coordinator: coordinator)
        }
    }

    @ViewBuilder private var downloadBar: some View {
        if let c = coordinator, c.phase != .complete {
            VStack(spacing: 2) {
                ProgressView(value: c.progress)
                Text(c.statusMessage).font(.caption2).foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
    }

    private func prepareDownload() async {
        guard await ModelManager.shared.localModels().isEmpty else { return }
        let models = await ModelManager.shared.recommendedModels()
        guard let best = models.first else { return }
        recommended = best
        let coord = ModelDownloadCoordinator(onComplete: { id in
            PreferencesStore.shared.completionModelID = id
            PreferencesStore.shared.serviceType = .local
            Task.detached(priority: .utility) { await CompletionEngine.shared.warmup() }
        })
        coordinator = coord
        await coord.start(modelID: best.id, url: best.url, sha: best.expectedSHA256)
    }
}

// MARK: - Step 0: Welcome
private struct WrenWelcomeStep: View {
    let recommended: ModelRecommendation?
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.cursor")
                .font(.system(size: 56)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("Welcome to Wren").font(.largeTitle.bold())
            Text("Wren predicts what you're about to type and shows it inline. Press Tab to accept.")
                .font(.title3).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 48)
            if let r = recommended {
                Text("Downloading \(r.name) in the background — \(r.reason)")
                    .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }.padding()
    }
}

// MARK: - Step 1: Input Monitoring
private struct InputMonitoringStep: View {
    @State private var granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: granted ? "checkmark.shield.fill" : "keyboard.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(granted ? Color.statusOk : Color.statusWarning)
                .symbolRenderingMode(.hierarchical)
            Text(granted ? "Permission granted!" : "Input Monitoring")
                .font(.title2.bold())
            Text(granted
                 ? "Wren can see what you type so it can suggest completions."
                 : "Wren needs Input Monitoring to read your keystrokes and offer inline completions. Nothing leaves your Mac.")
                .multilineTextAlignment(.center).foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 48)
            if !granted {
                Button("Grant access") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
                    .buttonStyle(.borderedProminent)
                Text("System Settings → Privacy & Security → Input Monitoring → enable Wren")
                    .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding()
        .task {
            while !Task.isCancelled, !granted {
                try? await Task.sleep(for: .milliseconds(600))
                granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            }
        }
    }
}

// MARK: - Step 3: Screen Context (optional)
private struct WrenScreenContextStep: View {
    @State private var granted = ScreenContextProvider.hasPermission
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 44)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("Smarter suggestions (optional)").font(.title2.bold())
            Text("Let Wren read the conversation above your cursor to suggest more relevant completions. You can skip this and enable it later.")
                .multilineTextAlignment(.center).foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 48)
            if !granted {
                Button("Enable screen context") { ScreenContextProvider.requestPermission() }
                    .buttonStyle(.bordered)
            } else {
                Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(Color.statusOk)
            }
            Spacer()
        }.padding()
    }
}

// MARK: - Step 4: Ready
private struct WrenReadyStep: View {
    let coordinator: ModelDownloadCoordinator?
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("You're ready").font(.largeTitle.bold())
            if let c = coordinator, c.phase != .complete {
                if case .failed(let msg) = c.phase {
                    Text("Model download failed: \(msg). Retry from Settings → Models.")
                        .font(.caption).foregroundStyle(Color.statusError)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                } else {
                    Text("Your model is still downloading — you can start now, it'll be ready in a moment.")
                        .font(.callout).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            } else {
                Text("Start typing anywhere and press Tab to accept Wren's suggestions.")
                    .font(.callout).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
                Text("⚠︎ Input Monitoring is off — enable it in System Settings for Wren to work.")
                    .font(.caption).foregroundStyle(Color.statusWarning)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer()
        }.padding()
    }
}

// MARK: - Tone Tune-Up Presenter

/// Opens the tone practice as a standalone window for the recurring tune-up.
@MainActor
enum ToneTuneUpPresenter {
    private static var window: NSWindow?

    static func presentIfDue() {
        guard AppMode.current.showsCompletion else { return }
        let prefs = PreferencesStore.shared
        guard ToneTuneUpScheduler.isDue(cadence: prefs.toneTuneUpCadence,
                                        lastRun: prefs.toneTuneUpLastRun) else { return }
        present()
    }

    static func present() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let seed = Int(Date().timeIntervalSince1970 / 86400)
        let phrases = TonePhrases.rotating(count: 3, seed: seed)
        let root = TonePracticeView(phrases: phrases, onLearned: { _ in
            PreferencesStore.shared.toneTuneUpLastRun = Date()
            window?.close(); window = nil
        })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Tone tune-up — Wren"
        w.center(); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AnyView(root.frame(width: 560, height: 420)))
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
