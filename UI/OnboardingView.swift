import SwiftUI
import ApplicationServices

// MARK: - Controller

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()

    private var window: NSWindow?

    nonisolated static func completionKey(for mode: AppMode) -> String {
        mode == .wren ? "hasCompletedOnboarding_wren_v1" : "hasCompletedOnboarding_v2"
    }

    func showIfNeeded() {
        let key = Self.completionKey(for: .current)
        guard !UserDefaults.standard.bool(forKey: key) else { return }
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
        w.title = "Initial Setup — \(AppMode.current.displayName)"
        w.center()
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("OnboardingWindow")

        let onComplete: () -> Void = { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completionKey(for: .current))
            self?.window?.close()
            self?.window = nil
        }
        let root: AnyView = AppMode.current.showsCompletion
            ? AnyView(WrenOnboardingView(onComplete: onComplete))
            : AnyView(ParrotOnboardingView(onComplete: onComplete))
        w.contentView = NSHostingView(rootView: root)

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root View

struct ParrotOnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var prefs = PreferencesStore.shared

    private let totalSteps = 8

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: step)

            Divider()
            bottomBar
        }
        .frame(width: 620, height: 520)
        .background(Color.surfaceBackground)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: InstallStep()
        case 1: WelcomeStep()
        case 2: AccessibilityStep()
        case 3: ServiceStep(prefs: prefs)
        case 4: LanguageStyleStep()
        case 5: ShortcutsStep()
        case 6: TryItStep()
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
                    .accessibilityLabel("Back")
            }

            Spacer()

            stepDots

            Spacer()

            Button("Skip") { onComplete() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .font(.callout)
                .accessibilityLabel("Skip")

            if step < totalSteps - 1 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Next")
            } else {
                Button("Start using Parrot") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Start using Parrot")
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

// MARK: - Step 0: Install

private struct InstallStep: View {
    @State private var isInApplications: Bool = {
        let appPath = "/Applications/Parrot.app"
        return FileManager.default.fileExists(atPath: appPath)
    }()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text("Install Parrot")
                    .font(.title.weight(.bold))

                if isInApplications {
                    Label("Parrot is installed in your Applications folder", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.statusOk)
                } else {
                    Text("Drag Parrot to Applications to complete installation.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Drag diagram
            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.surfaceElevated)
                            .frame(width: 96, height: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: Color.accentColor.opacity(0.1), radius: 8, x: 0, y: 2)
                        Text("🦜").font(.system(size: 52))
                    }
                    Text("Parrot.app")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Image(systemName: "arrow.right")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 80)

                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.surfaceElevated)
                            .frame(width: 96, height: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.accentBrand.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: Color.accentBrand.opacity(0.08), radius: 8, x: 0, y: 2)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentBrand)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text("Applications")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(20)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
            )

            if !isInApplications {
                Button("Open Applications Folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open Applications Folder")
            }

            // Gatekeeper note
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.statusWarning)
                    .font(.callout)
                    .padding(.top, 1)
                Text("If macOS shows **\"Apple cannot verify…\"**: right-click Parrot → **Open** → **Open** in the dialog. This only happens once.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.statusWarning.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @State private var welcomePulse = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("🦜")
                .font(.system(size: 72))
                .scaleEffect(welcomePulse ? 1.0 : 0.85)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: welcomePulse)
                .onAppear { welcomePulse = true }

            VStack(spacing: 10) {
                Text("Welcome to Parrot")
                    .font(.largeTitle.weight(.bold))

                Text("Your minimal, clever writing companion for Mac")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 12) {
                FeatureRow(icon: "text.badge.checkmark", color: .accentGreen,
                           title: "Grammar anywhere",
                           subtitle: "Select text in any app and press ⌘⇧E")
                FeatureRow(icon: "sparkles", color: .accentPurple,
                           title: "Improve fluency",
                           subtitle: "Make your text more natural and readable")
                FeatureRow(icon: "lock.shield", color: .accentBrand,
                           title: "Your words stay yours",
                           subtitle: "All processing is local. No data ever leaves your Mac.")
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
                    .foregroundStyle(Color.textSecondary)
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
                    .fill(isGranted ? Color.statusOk.opacity(0.12) : Color.statusWarning.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: isGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isGranted ? Color.statusOk : Color.statusWarning)
                    .symbolRenderingMode(.hierarchical)
            }
            .animation(.spring(response: 0.4), value: isGranted)

            VStack(spacing: 10) {
                Text(isGranted ? "Permissions granted!" : "Accessibility Permissions")
                    .font(.title2.bold())

                Text(isGranted
                    ? "Parrot can now read and modify text in other applications."
                    : "Parrot needs access to text in other applications to correct grammar."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 48)
            }

            if !isGranted {
                VStack(spacing: 12) {
                    Button("Open System Settings") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Open System Settings")

                    Text("System Settings → Privacy & Security → Accessibility → add Parrot")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)
                }
            }

            Spacer()
        }
        .padding()
        .task {
            while !Task.isCancelled, !isGranted {
                try? await Task.sleep(for: .milliseconds(600))
                isGranted = AXIsProcessTrusted()
            }
        }
    }
}

// MARK: - Step 2: AI Service
// Extracted to UI/ServiceStep.swift

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
                    .foregroundStyle(Color.textSecondary)
                    .font(.title3)
            }

            VStack(spacing: 12) {
                FeatureRow(icon: "globe", color: .accentBrand,
                           title: "Language",
                           subtitle: "Detected automatically from the selected text using Apple's NLP framework")
                FeatureRow(icon: "text.alignleft", color: .accentPurple,
                           title: "Writing style",
                           subtitle: "Inferred from context — formal email, casual chat, technical docs, academic writing")
                FeatureRow(icon: "apps.iphone", color: .accentGreen,
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
                    .foregroundStyle(Color.textSecondary)
                    .font(.callout)
            }

            VStack(spacing: 2) {
                ShortcutRow(keys: "⌘⇧E", action: "Check Grammar",
                            detail: "Corrects the selected text")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧T", action: "Check Fluency",
                            detail: "Makes text more natural and readable")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧U", action: "Translate",
                            detail: "Translates to your target language")
                Divider().padding(.horizontal, 48)
                ShortcutRow(keys: "⌘⇧W", action: "Writing Coach",
                            detail: "Get structured feedback on your writing")
            }
            .padding(.horizontal, 48)

            Text("All shortcuts are customizable in Settings → Shortcuts.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

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
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.borderDefault.opacity(0.5), lineWidth: 1)
                )
                .frame(width: 72, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(action)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 6: Try It Now

private struct TryItStep: View {
    @State private var sampleText = "He go to the store yesterday and buyed some milks."
    @State private var isCorrecting = false
    @State private var correctedText = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Try it now")
                    .font(.title2.bold())
                Text("See Parrot in action with this sample text.")
                    .foregroundStyle(Color.textSecondary)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Original:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextEditor(text: $sampleText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .padding(8)
                    .background(Color.surfaceBackground, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(isCorrecting)
            }
            .padding(.horizontal, 48)

            if !correctedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Corrected:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.statusOk)
                    Text(correctedText)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.statusOk.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 48)
            }

            Button(action: {
                isCorrecting = true
                correctedText = "He went to the store yesterday and bought some milk."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    isCorrecting = false
                }
            }) {
                if isCorrecting {
                    ProgressView().scaleEffect(0.8)
                } else if correctedText.isEmpty {
                    Label("Correct this text", systemImage: "text.badge.checkmark")
                } else {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCorrecting)

            Text("This is a demo — the real correction uses an AI model.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 6: Ready

private struct ReadyStep: View {
    let prefs: PreferencesStore
    @State private var celebrationPulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 8)

                Image(systemName: "party.popper.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(celebrationPulse ? 1.0 : 0.7)
                    .opacity(celebrationPulse ? 1.0 : 0.4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.15), value: celebrationPulse)
                    .onAppear { celebrationPulse = true }

                VStack(spacing: 6) {
                    Text("All set!")
                        .font(.largeTitle.weight(.bold))
                    Text("You're ready to write better, faster.")
                        .foregroundStyle(Color.textSecondary)
                        .font(.title3)
                }

                // Status recap
                VStack(alignment: .leading, spacing: 10) {
                    ReadyCheckRow(
                        icon: "checkmark.circle.fill", color: .accentGreen,
                        text: "AI engine: \(prefs.serviceType.rawValue.capitalized)"
                    )
                    ReadyCheckRow(
                        icon: "checkmark.circle.fill", color: .accentGreen,
                        text: "Language & style: auto-detected"
                    )
                    ReadyCheckRow(
                        icon: "checkmark.circle.fill", color: .accentGreen,
                        text: "Global shortcuts active"
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                )
                .padding(.horizontal, 40)

                // Feature guide
                VStack(alignment: .leading, spacing: 16) {
                    Text("Start here")
                        .font(.headline.weight(.semibold))

                    FeatureGuideCard(
                        icon: "text.badge.checkmark",
                        title: "Quick check",
                        description: "Select text in any app, press the shortcut key. Parrot analyzes and shows corrections instantly in a floating panel."
                    )
                    FeatureGuideCard(
                        icon: "keyboard",
                        title: "Keyboard shortcuts",
                        description: "⌘⇧E checks grammar, ⌘⇧F checks fluency, ⌘⇧T translates, ⌘⇧I opens the floating editor. All configurable in Preferences."
                    )
                    FeatureGuideCard(
                        icon: "switch.2",
                        title: "Automatic & real-time modes",
                        description: "Enable 'Automatic check' to analyze every text field you click into. 'Real time' checks while you type."
                    )
                    FeatureGuideCard(
                        icon: "rectangle.and.pencil.and.ellipsis",
                        title: "Floating editor",
                        description: "Open the floating editor from the menu bar to paste or type text and get corrections without leaving your current app."
                    )
                    FeatureGuideCard(
                        icon: "gearshape.2",
                        title: "Custom rules & presets",
                        description: "Create custom find-and-replace rules, save prompt presets, and adjust writing style preferences in Settings."
                    )
                    FeatureGuideCard(
                        icon: "arrow.up.arrow.down.circle",
                        title: "Translation & more",
                        description: "Translate selected text, use presets for different writing contexts, and access advanced features from the menu bar."
                    )
                }
                .padding(.horizontal, 40)

                Text("Select text in any app and press ⌘⇧E. That's it.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer().frame(height: 8)
            }
        }
    }
}

private struct FeatureGuideCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
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

#Preview {
    ParrotOnboardingView(onComplete: {})
}
