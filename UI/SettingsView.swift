import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false
    @State private var selectedTab: SettingsTab = .prompt

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section {
                    Label("Engine", systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                }
                NavigationLink(value: SettingsTab.models) {
                    Label(SettingsTab.models.label, systemImage: SettingsTab.models.icon)
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
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)

            Divider()

            selectedTab.destination(prefs: prefs, serverIsRunning: serverIsRunning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
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
        }
    }

    static let behaviorTabs: [SettingsTab] = [.prompt, .appRules, .customRules, .exclusions, .inlineAnnotations, .dictionary, .shortcuts, .presets]
    static let dataTabs: [SettingsTab] = [.history, .exportImport, .iCloud, .knowledge, .contacts]
    static let systemTabs: [SettingsTab] = [.advanced, .plagiarism]

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
        case .advanced:    AdvancedTab()
        case .inlineAnnotations: InlineAnnotationsTab(prefs: prefs)
        case .history:     HistoryTab()
        case .exportImport: ExportImportTab()
        case .iCloud:      iCloudSyncTab()
        case .knowledge:   KnowledgeBaseTab()
        case .plagiarism:  PlagiarismTab()
        case .contacts:    ContactsSettingsTab()
        }
    }
}

#Preview {
    SettingsView()
}
