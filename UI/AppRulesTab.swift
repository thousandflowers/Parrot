import SwiftUI

struct AppRulesTab: View {
    @Bindable var prefs: PreferencesStore

    var body: some View {
        Form {
            Text("App rules")
        }
    }
}
