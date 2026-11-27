import SwiftUI

@main
struct ParrotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        // URL events (parrot://correct from PopClip/deep links) belong to AppDelegate. Without this,
        // SwiftUI treats them as "open a scene" and pops the Settings window over the user's work.
        .handlesExternalEvents(matching: [])
    }
}
