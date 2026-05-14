import SwiftUI

struct AdvancedTab: View {
    var body: some View {
        Form {
            Section("Debug") {
                Text("Accessibilità: \(PreferencesStore.shared.isAccessibilityEnabled ? "OK" : "Non abilitata")")
                Text("Bundle: \(Constants.bundleID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
