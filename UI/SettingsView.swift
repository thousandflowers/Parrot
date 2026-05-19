import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Generale", systemImage: "gearshape") }

            ModelsTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Modelli", systemImage: "brain") }

            PromptTab(prefs: prefs)
                .tabItem { Label("Prompt", systemImage: "text.quote") }

            AppRulesTab(prefs: prefs)
                .tabItem { Label("Regole App", systemImage: "apps.iphone") }

            ExclusionsTab(prefs: prefs)
                .tabItem { Label("Esclusioni", systemImage: "eye.slash") }

            ShortcutsTab(prefs: prefs)
                .tabItem { Label("Scorciatoie", systemImage: "keyboard") }

            PresetsTab(prefs: prefs)
                .tabItem { Label("Preset", systemImage: "star") }

            AdvancedTab()
                .tabItem { Label("Avanzate", systemImage: "wrench.adjustable") }

            HistoryTab()
                .tabItem { Label("Cronologia", systemImage: "clock") }
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
