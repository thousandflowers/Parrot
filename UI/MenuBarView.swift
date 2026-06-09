import SwiftUI
import ApplicationServices

struct MenuBarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prefs = PreferencesStore.shared
    @State private var actionsExpanded = true
    @State private var utilityExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                Divider()

                if !prefs.isAccessibilityEnabled {
                    accessibilityBanner
                    Divider()
                }

                if AppMode.current.showsCorrection {
                    serviceSection
                    Divider()
                }

                if AppMode.current.showsCompletion && prefs.inlineCompletionEnabled && prefs.completionModelID.isEmpty {
                    completionBackendBanner
                    Divider()
                }

                toggleSection
                Divider()

                if AppMode.current.showsCorrection {
                    actionsSection
                    Divider()
                }

                utilitySection
                Divider()

                quitRow
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.apple.accessibility.api"))) { _ in
            if !prefs.isAccessibilityEnabled { prefs.refreshAccessibility() }
        }
    }

    // MARK: - Header

    @State private var headerHovered = false

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.surfaceElevated)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
                    )
                Text("🦜")
                    .font(.system(size: 18))
            }
            .scaleEffect(headerHovered ? 1.07 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55), value: headerHovered)
            .onHover { headerHovered = $0 }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppMode.current.displayName)
                    .font(.title3.weight(.bold))
                Text(serviceSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Status dot
            Circle()
                .fill(serverStatusColor)
                .frame(width: 8, height: 8)
                .shadow(color: serverStatusColor.opacity(0.35), radius: 1.5, x: 0, y: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var serverStatusColor: Color {
        switch prefs.serviceType {
        case .stub: return .statusWarning
        case .appleIntelligence:
            if #available(macOS 26.0, *) {
                return AppleIntelligenceService.shared.isAvailable ? .statusOk : .statusError
            }
            return .statusWarning
        default: return .statusOk
        }
    }

    // MARK: - Accessibility banner

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.statusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility permission needed")
                        .font(.callout.weight(.semibold))
                    Text("Required to read and correct text in other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: openAccessibilitySettings) {
                Label("Enable in System Settings", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Text("If Parrot is already listed, try toggling it off and on again.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.statusWarning.opacity(0.08))
    }

    private func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Completion backend banner (Wren mode)

    private var completionBackendBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.badge.exclamationmark")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.statusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No completion model configured")
                        .font(.callout.weight(.semibold))
                    Text("Completion uses the server fallback. For best performance, pick a dedicated model in settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsLink {
                Label("Open settings", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.statusWarning.opacity(0.08))
    }

    private var serviceSubtitle: String {
        switch prefs.serviceType {
        case .local:
            if AppMode.current.showsCompletion {
                // Wren completes with the dedicated/bundled model — show that, not the correction model.
                let cid = (UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.completionModelID) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                return "Local · \(cid.isEmpty ? "bundled model" : cid)"
            }
            return "Local · \(prefs.selectedModelID.isEmpty ? "no model" : prefs.selectedModelID)"
        case .ollama:            return "Ollama · \(prefs.ollamaModel)"
        case .remote:            return "OpenAI · \(prefs.openAIModel)"
        case .openRouter:        return "OpenRouter · \(prefs.openRouterModel)"
        case .appleIntelligence: return "Apple Intelligence"
        case .mlx:               return "MLX · \(MLXLLMService.shared.selectedModelID)"
        case .stub:              return "Stub (no connection)"
        }
    }

    // MARK: - Service row

    private var serviceSection: some View {
        HStack(spacing: 8) {
            Image(systemName: serviceIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(serviceStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            SettingsLink {
                Text("Configure")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var serviceIcon: String {
        switch prefs.serviceType {
        case .local:             return "cpu"
        case .ollama:            return "server.rack"
        case .remote:            return "cloud"
        case .openRouter:        return "network"
        case .appleIntelligence: return "apple.logo"
        case .mlx:               return "bolt.fill"
        case .stub:              return "wrench.and.screwdriver"
        }
    }

    private var serviceStatusLabel: String {
        switch prefs.serviceType {
        case .stub: return "No service configured"
        case .appleIntelligence:
            if #available(macOS 26.0, *) {
                return AppleIntelligenceService.shared.isAvailable
                    ? "Apple Intelligence · On-device"
                    : "Apple Intelligence · Not available"
            }
            return "Apple Intelligence · Requires macOS 26"
        default:    return serviceSubtitle
        }
    }

    // MARK: - Toggles

    private var toggleSection: some View {
        VStack(spacing: 0) {
            if AppMode.current.showsCorrection {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Automatic check")
                            .font(.callout)
                        Text("On text field activation")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $prefs.autoCheckEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .accessibilityLabel("Automatic check")
                        .accessibilityHint("When enabled, checks text every time you activate a text field")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                Divider()
                    .padding(.leading, 16)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Real time")
                            .font(.callout)
                        Text("Analyzes while you type")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $prefs.realtimeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .accessibilityLabel("Real time")
                        .accessibilityHint("When enabled, analyzes text while you type")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)

                Divider()
                    .padding(.leading, 16)
            }

            if AppMode.current.showsCompletion {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Inline completion")
                        .font(.callout)
                    Text("Ghost suggestions · press Tab")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
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
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Inline completion")
                .accessibilityHint("When enabled, shows ghost text suggestions while typing. Press Tab to accept.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            }

            // Focus Mode section
            Divider()
                .padding(.leading, 16)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Raw draft mode")
                        .font(.callout)
                    Text("No suggestions · no corrections")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { FocusMode.shared.isRawDraft },
                    set: { newValue in
                        if newValue {
                            FocusMode.shared.enterRawDraft()
                            if prefs.realtimeEnabled { Task { await RealtimeMonitor.shared.suspend() } }
                        } else {
                            FocusMode.shared.exitRawDraft()
                            if prefs.realtimeEnabled { Task { await RealtimeMonitor.shared.resume() } }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Raw draft mode")
                .accessibilityHint("Disables suggestions and corrections so you can write freely.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            // Start session
            Button {
                FocusSessionPanel.shared.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .center)
                    Text("Start focus session")
                        .font(.callout)
                    Spacer()
                    if FocusStatsStore.shared.currentStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("\(FocusStatsStore.shared.currentStreak)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions (collapsible)

    private var actionsSection: some View {
        DisclosureGroup(isExpanded: $actionsExpanded) {
            VStack(spacing: 0) {
                MenuAction(icon: "text.badge.checkmark", title: "Check Grammar", iconColor: .accentGreen, shortcut: shortcutString(prefs.shortcutGrammar), hint: "Fix grammatical errors in selected text") { checkGrammar() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "sparkles", title: "Check Fluency", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutFluency), hint: "Improve clarity and flow of selected text") { checkFluency() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "text.badge.star", title: "Grammar + Fluency", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutGrammarFluency), hint: "Fix grammar and improve fluency in one pass") { checkGrammarFluency() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "character.book.closed", title: "Translate", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutTranslate), hint: "Translate selected text") { checkTranslate() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "magnifyingglass", title: "Plagiarism Check", iconColor: .statusWarning, hint: "Check selected text for copied content") { checkPlagiarism() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "text.cursor", title: "Open Editor", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutEditor), hint: "Open floating editor for longer texts") { openEditor() }
            }
        } label: {
            sectionLabel("ACTIONS", isExpanded: actionsExpanded)
                .padding(.trailing, 4)
        }
        .disclosureGroupStyle(QuietDisclosureStyle())
        .padding(.vertical, 4)
    }

    // MARK: - Utility (collapsible)

    private var utilitySection: some View {
        DisclosureGroup(isExpanded: $utilityExpanded) {
            VStack(spacing: 0) {
                SettingsLink {
                    MenuActionLabel(icon: "gearshape", title: "Preferences…", shortcut: "⌘,")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
                .buttonStyle(MenuRowButtonStyle())

                Divider().padding(.leading, 44)

                MenuAction(icon: "arrow.down.circle", title: "Check for updates…") {
                    AppUpdater.shared.checkForUpdates()
                }

                Divider().padding(.leading, 44)

                MenuAction(icon: "ladybug", title: "Report a Bug…") {
                    if let url = URL(string: "https://github.com/thousandflowers/Parrot/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } label: {
            sectionLabel("UTILITY", isExpanded: utilityExpanded)
                .padding(.trailing, 4)
        }
        .disclosureGroupStyle(QuietDisclosureStyle())
        .padding(.vertical, 4)
    }

    // MARK: - Quit

    private var quitRow: some View {
        Button(action: { NSApplication.shared.terminate(nil) }) {
            HStack(spacing: 10) {
                Image(systemName: "power")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
                Text("Quit \(AppMode.current.displayName)")
                    .font(.callout)
                Spacer()
                Text("⌘Q")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ text: String, isExpanded: Bool) -> some View {
        HStack {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary.opacity(0.6))
                .rotationEffect(isExpanded ? .degrees(0) : .degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func shortcutString(_ config: ShortcutConfig) -> String {
        config.isEnabled ? config.displayString : ""
    }

    // MARK: - Actions

    private func perform(_ action: () -> Void) { action() }

    private func checkGrammar()        { perform { TextCheckCoordinator.shared.checkSelectedText() } }
    private func checkFluency()        { perform { TextCheckCoordinator.shared.checkFluency() } }
    private func checkGrammarFluency() { perform { TextCheckCoordinator.shared.checkGrammarThenFluency() } }
    private func checkTranslate()      { perform { TextCheckCoordinator.shared.checkTranslation() } }
    private func checkPlagiarism()     { perform { TextCheckCoordinator.shared.checkPlagiarism() } }

    private func openEditor() {
        Task { await TextCheckCoordinator.shared.openFloatingEditor() }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Components

private struct MenuAction: View {
    let icon: String
    let title: String
    var iconColor: Color? = nil
    var shortcut: String? = nil
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuActionLabel(icon: icon, title: title, iconColor: iconColor, shortcut: shortcut)
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

private struct MenuActionLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: String
    var iconColor: Color? = nil
    var shortcut: String? = nil
    @State private var iconHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor ?? .secondary)
                .frame(width: 16, alignment: .center)
                .scaleEffect(iconHovered ? 1.2 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: iconHovered)
            Text(title)
                .font(.callout)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { iconHovered = $0 }
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if configuration.isPressed {
                        Color.accentColor.opacity(0.18)
                    } else if isHovered {
                        Color.primary.opacity(0.06)
                    } else {
                        Color.clear
                    }
                }
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}

// MARK: - Disclosure Group Style

private struct QuietDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                if reduceMotion {
                    configuration.isExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.70)) {
                        configuration.isExpanded.toggle()
                    }
                }
            } label: {
                configuration.label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Expand or collapse section")

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }
}

#Preview {
    MenuBarView()
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
}
