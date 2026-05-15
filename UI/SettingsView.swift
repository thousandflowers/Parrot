import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Generale", systemImage: "gearshape") }
                .tag(0)
                .accessibilityElement(children: .contain)

            ModelsTab(prefs: prefs, serverIsRunning: serverIsRunning)
                .tabItem { Label("Modelli", systemImage: "brain") }
                .tag(1)
                .accessibilityElement(children: .contain)

            PromptTab(prefs: prefs)
                .tabItem { Label("Prompt", systemImage: "text.quote") }
                .tag(2)
                .accessibilityElement(children: .contain)

            AppRulesTab(prefs: prefs)
                .tabItem { Label("Regole App", systemImage: "apps.iphone") }
                .tag(3)
                .accessibilityElement(children: .contain)

            ExclusionsTab(prefs: prefs)
                .tabItem { Label("Esclusioni", systemImage: "eye.slash") }
                .tag(4)
                .accessibilityElement(children: .contain)

            AdvancedTab()
                .tabItem { Label("Avanzate", systemImage: "wrench.adjustable") }
                .tag(5)
                .accessibilityElement(children: .contain)

            HistoryTab()
                .tabItem { Label("Storia", systemImage: "clock") }
                .tag(6)
                .accessibilityElement(children: .contain)
        }
        .frame(minWidth: 500, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .task {
            serverIsRunning = await ServerManager.shared.currentPort > 0
            let stream = AsyncStream<Void> { continuation in
                let task = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        if Task.isCancelled { break }
                        continuation.yield(())
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            for await _ in stream {
                guard selectedTab <= 1 else { continue }
                let running = await ServerManager.shared.currentPort > 0
                guard running != serverIsRunning else { continue }
                serverIsRunning = running
            }
        }
    }
}
