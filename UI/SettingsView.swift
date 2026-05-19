import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("General", systemImage: "gearshape") }

            ModelsTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Models", systemImage: "brain") }

            PromptTab(prefs: prefs)
                .tabItem { Label("Prompt", systemImage: "text.quote") }

            AppRulesTab(prefs: prefs)
                .tabItem { Label("App Rules", systemImage: "apps.iphone") }

            ExclusionsTab(prefs: prefs)
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }

            ShortcutsTab(prefs: prefs)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            PresetsTab(prefs: prefs)
                .tabItem { Label("Presets", systemImage: "star") }

            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "wrench.adjustable") }

            HistoryTab()
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(minWidth: 560, minHeight: 420)
        .task {
            serverIsRunning = await ServerManager.shared.currentPort > 0
            for await _ in pollingStream() {
                let running = await ServerManager.shared.currentPort > 0
                if running != serverIsRunning { serverIsRunning = running }
            }
        }
    }

    private func pollingStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    if Task.isCancelled { break }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
