import SwiftUI

struct SettingsView: View {
    @State private var prefs = PreferencesStore.shared
    @State private var serverIsRunning = false
    @State private var selectedTab = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            ShortcutsTab(prefs: prefs)
                .tabItem { Label("Scorciatoie", systemImage: "keyboard") }
                .tag(5)
                .accessibilityElement(children: .contain)

            AdvancedTab()
                .tabItem { Label("Avanzate", systemImage: "wrench.adjustable") }
                .tag(6)
                .accessibilityElement(children: .contain)

            CustomRulesView()
                .tabItem { Label("Regole Custom", systemImage: "list.bullet.clipboard") }
                .tag(7)
                .accessibilityElement(children: .contain)
        }
        .frame(minWidth: 540, minHeight: 540)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
        .task {
            serverIsRunning = await ServerManager.shared.currentPort > 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard selectedTab <= 1 else { continue }
                let running = await ServerManager.shared.currentPort > 0
                if running != serverIsRunning { serverIsRunning = running }
            }
        }
    }
}
