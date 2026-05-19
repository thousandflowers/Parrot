import SwiftUI

@main
struct ParrotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Parrot", systemImage: "checkmark.shield") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
