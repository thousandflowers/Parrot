import SwiftUI

struct MenuBarView: View {
    @State private var prefs = PreferencesStore.shared

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
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
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Text("🦜")
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Parrot")
                    .font(.headline)
                Text(serviceSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            accessibilityBadge
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var serviceSubtitle: String {
        switch prefs.serviceType {
        case .local:       return "Local · \(prefs.selectedModelID.isEmpty ? "no model" : prefs.selectedModelID)"
        case .ollama:      return "Ollama · \(prefs.ollamaModel)"
        case .remote:      return "OpenAI · \(prefs.openAIModel)"
        case .openRouter:  return "OpenRouter · \(prefs.openRouterModel)"
        case .stub:        return "Stub (no connection)"
        }
    }

    @ViewBuilder
    private var accessibilityBadge: some View {
        if prefs.isAccessibilityEnabled {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .help("Accessibility active")
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Acc.")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.12), in: Capsule())
            .help("Accessibility: permission required")
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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var serviceIcon: String {
        switch prefs.serviceType {
        case .local:      return "cpu"
        case .ollama:     return "server.rack"
        case .remote:     return "cloud"
        case .openRouter: return "network"
        case .stub:       return "wrench.and.screwdriver"
        }
    }

    private var serviceStatusLabel: String {
        switch prefs.serviceType {
        case .stub: return "No service configured"
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .padding(.leading, 14)

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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Primary actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            sectionLabel("ACTIONS")
            MenuAction(icon: "text.badge.checkmark", title: "Check Grammar", shortcut: shortcutString(prefs.shortcutGrammar)) { checkGrammar() }
            MenuAction(icon: "sparkles", title: "Check Fluency", shortcut: shortcutString(prefs.shortcutFluency)) { checkFluency() }
            MenuAction(icon: "text.cursor", title: "Open Editor", shortcut: shortcutString(prefs.shortcutEditor)) { openEditor() }
        }
    }

    // MARK: - Utility

    private var utilitySection: some View {
        VStack(spacing: 0) {
            SettingsLink {
                MenuActionLabel(icon: "gearshape", title: "Preferences…", shortcut: "⌘,")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(MenuRowButtonStyle())

            MenuAction(icon: "arrow.down.circle", title: "Check for updates…") {
                AppUpdater.shared.checkForUpdates()
            }

            MenuAction(icon: "ladybug", title: "Report a Bug…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/thousandflowers/Parrot/issues/new")!)
            }
        }
    }

    // MARK: - Quit

    private var quitRow: some View {
        MenuAction(icon: "power", title: "Quit Parrot") {
            NSApplication.shared.terminate(nil)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func shortcutString(_ config: ShortcutConfig) -> String {
        config.isEnabled ? config.displayString : ""
    }

    // MARK: - Actions

    private func checkGrammar() {
        NSApp.deactivate()
        TextCheckCoordinator.shared.checkSelectedText()
    }

    private func checkFluency() {
        NSApp.deactivate()
        TextCheckCoordinator.shared.checkFluency()
    }

    private func openEditor() {
        Task { await TextCheckCoordinator.shared.openFloatingEditor() }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Components

private struct MenuAction: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuActionLabel(icon: icon, title: title, shortcut: shortcut)
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

private struct MenuActionLabel: View {
    let icon: String
    let title: String
    var shortcut: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
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
