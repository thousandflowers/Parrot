import SwiftUI
import ApplicationServices

struct MenuBarView: View {
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

                serviceSection
                Divider()

                toggleSection
                Divider()

                actionsSection
                Divider()

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
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
                    )
                Text("🦜")
                    .font(.system(size: 18))
            }
            .scaleEffect(headerHovered ? 1.07 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: headerHovered)
            .onHover { headerHovered = $0 }

            VStack(alignment: .leading, spacing: 2) {
                Text("Parrot")
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
                .shadow(color: serverStatusColor.opacity(0.4), radius: 2, x: 0, y: 0)
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

    private var serviceSubtitle: String {
        switch prefs.serviceType {
        case .local:             return "Local · \(prefs.selectedModelID.isEmpty ? "no model" : prefs.selectedModelID)"
        case .ollama:            return "Ollama · \(prefs.ollamaModel)"
        case .remote:            return "OpenAI · \(prefs.openAIModel)"
        case .openRouter:        return "OpenRouter · \(prefs.openRouterModel)"
        case .appleIntelligence: return "Apple Intelligence"
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    // MARK: - Actions (collapsible)

    private var actionsSection: some View {
        DisclosureGroup(isExpanded: $actionsExpanded) {
            VStack(spacing: 0) {
                MenuAction(icon: "text.badge.checkmark", title: "Check Grammar", iconColor: .accentGreen, shortcut: shortcutString(prefs.shortcutGrammar)) { checkGrammar() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "sparkles", title: "Check Fluency", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutFluency)) { checkFluency() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "text.badge.star", title: "Grammar + Fluency", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutGrammarFluency)) { checkGrammarFluency() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "character.book.closed", title: "Translate", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutTranslate)) { checkTranslate() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "magnifyingglass", title: "Plagiarism Check", iconColor: .statusWarning) { checkPlagiarism() }
                Divider().padding(.leading, 44)
                MenuAction(icon: "text.cursor", title: "Open Editor", iconColor: .secondary, shortcut: shortcutString(prefs.shortcutEditor)) { openEditor() }
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
        HStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
            Text("Quit Parrot")
                .font(.callout)
            Spacer()
            Text("⌘Q")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { NSApplication.shared.terminate(nil) }
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
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isExpanded)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuActionLabel(icon: icon, title: title, iconColor: iconColor, shortcut: shortcut)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

private struct MenuActionLabel: View {
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
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: iconHovered)
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
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                configuration.label
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }
}

#Preview {
    MenuBarView()
        .frame(width: 320)
}
