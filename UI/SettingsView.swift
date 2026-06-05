import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false
    @State private var selectedTab: SettingsTab = AppMode.current.showsCompletion ? .completion : .prompt

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                // P2.3: Keyboard focus — the sidebar uses NavigationLink which gets
                // natural focus order via the List. Section headers are non-interactive
                // so tab skips to the first NavigationLink automatically.
                Section {
                    Label("Engine", systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
                // Wren drives completion from a single local .gguf (in-process helper);
                // the full multi-service Models tab is Parrot-only.
                let engineTab: SettingsTab = AppMode.current.showsCompletion ? .completionModel : .models
                NavigationLink(value: engineTab) {
                    Label(engineTab.label, systemImage: engineTab.icon)
                }

                Section {
                    Label("Behavior", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
                ForEach(SettingsTab.behaviorTabs) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }

                Section {
                    Label("Data", systemImage: "cylinder.split.1x2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
                ForEach(SettingsTab.dataTabs) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }

                Section {
                    Label("System", systemImage: "gearshape.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
                ForEach(SettingsTab.systemTabs) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(.accentColor)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)

            Divider()

            selectedTab.destination(prefs: prefs, serverIsRunning: serverIsRunning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
                .background(AccessibilityScrollCleaner())
        }
        .frame(minWidth: 680, minHeight: 420)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .task {
            serverIsRunning = await ServerManager.shared.currentPort > 0
            for await _ in NotificationCenter.default.publisher(for: .serverStateDidChange).values {
                let running = await ServerManager.shared.currentPort > 0
                if running != serverIsRunning { serverIsRunning = running }
            }
        }
    }
}

// MARK: - Tab definitions

private enum SettingsTab: String, CaseIterable, Identifiable {
    case models, prompt, appRules, customRules, exclusions
    case dictionary, shortcuts, presets, advanced, history
    case exportImport, iCloud, knowledge, plagiarism
    case inlineAnnotations
    case contacts
    case completion
    case dashboard
    case focus
    case completionModel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .models:      return "Models"
        case .prompt:      return "Prompt"
        case .appRules:    return "App Rules"
        case .customRules: return "Custom Rules"
        case .exclusions:  return "Exclusions"
        case .dictionary:  return "Dictionary"
        case .shortcuts:   return "Shortcuts"
        case .presets:     return "Presets"
        case .advanced:    return "Advanced"
        case .history:     return "History"
        case .exportImport: return "Export/Import"
        case .iCloud:      return "iCloud"
        case .knowledge:   return "Knowledge"
        case .plagiarism:  return "Plagiarism"
        case .inlineAnnotations: return "Inline"
        case .contacts:     return "Contacts"
        case .completion:   return "Completion"
        case .dashboard:    return "Dashboard"
        case .focus:        return "Focus"
        case .completionModel: return "Model"
        }
    }

    var icon: String {
        switch self {
        case .models:      return "brain"
        case .prompt:      return "text.quote"
        case .appRules:    return "apps.iphone"
        case .customRules: return "pencil.tip.crop.circle"
        case .exclusions:  return "eye.slash"
        case .dictionary:  return "book"
        case .shortcuts:   return "keyboard"
        case .presets:     return "star"
        case .advanced:    return "wrench.adjustable"
        case .history:     return "clock"
        case .exportImport: return "arrow.2.circlepath"
        case .iCloud:      return "icloud"
        case .knowledge:   return "book.closed"
        case .plagiarism:  return "magnifyingglass"
        case .inlineAnnotations: return "text.badge.checkmark"
        case .contacts:     return "person.2"
        case .completion:   return "text.append"
        case .dashboard:    return "chart.bar"
        case .focus:        return "target"
        case .completionModel: return "cpu"
        }
    }

    // Tabs are mode-specific: Canary shows completion + shared settings; Parrot shows correction.
    static var behaviorTabs: [SettingsTab] {
        AppMode.current.showsCompletion
            ? [.completion, .exclusions, .shortcuts, .focus, .dashboard]
            : [.prompt, .appRules, .customRules, .exclusions, .inlineAnnotations, .dictionary, .shortcuts, .presets, .focus]
    }
    static var dataTabs: [SettingsTab] {
        AppMode.current.showsCompletion ? [.exportImport] : [.history, .exportImport, .iCloud, .knowledge, .contacts]
    }
    static var systemTabs: [SettingsTab] {
        AppMode.current.showsCompletion ? [.advanced] : [.advanced, .plagiarism]
    }

    @ViewBuilder
    func destination(prefs: PreferencesStore, serverIsRunning: Bool) -> some View {
        switch self {
        case .models:      ModelsTab(prefs: prefs, serverIsRunning: serverIsRunning)
        case .prompt:      PromptTab(prefs: prefs)
        case .appRules:    AppRulesTab(prefs: prefs)
        case .customRules: CustomRulesView()
        case .exclusions:  ExclusionsTab(prefs: prefs)
        case .dictionary:  IgnoreListTab()
        case .shortcuts:   ShortcutsTab(prefs: prefs)
        case .presets:     PresetsTab(prefs: prefs)
        case .advanced:    AdvancedTab(prefs: prefs)
        case .inlineAnnotations: InlineAnnotationsTab(prefs: prefs)
        case .completion:  CompletionTab(prefs: prefs)
        case .dashboard:   DashboardTab()
        case .history:     HistoryTab()
        case .exportImport: ExportImportTab()
        case .iCloud:      iCloudSyncTab()
        case .knowledge:   KnowledgeBaseTab()
        case .plagiarism:  PlagiarismTab()
        case .contacts:    ContactsSettingsTab()
        case .focus:       FocusTab(prefs: prefs)
        case .completionModel: CompletionModelTab(prefs: prefs)
        }
    }
}

// MARK: - AX Scroll Cleaner

/// NSViewRepresentable that walks the superview chain to find NSScrollViews
/// and hides their scrollers from the accessibility tree. This prevents ghost
/// AX elements (size 0×0 for scroll track, thumb, arrows) that SwiftUI leaks
/// on macOS. The scrollers remain visually present.
private struct AccessibilityScrollCleaner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        DispatchQueue.main.async {
            var current = view.superview
            while let c = current {
                if let sv = c as? NSScrollView {
                    sv.verticalScroller?.setAccessibilityElement(false)
                    sv.horizontalScroller?.setAccessibilityElement(false)
                }
                current = c.superview
            }
        }
        return view
    }
    func updateNSView(_: NSView, context: Context) {}
}

#Preview {
    SettingsView()
}
