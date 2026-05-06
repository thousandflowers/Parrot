import SwiftUI

@main
struct RefineCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("RefineClone", systemImage: "checkmark.shield") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
