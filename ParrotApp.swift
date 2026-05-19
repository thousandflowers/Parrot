import SwiftUI

@main
struct ParrotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Text("🦜")
                .font(.system(size: 14))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
