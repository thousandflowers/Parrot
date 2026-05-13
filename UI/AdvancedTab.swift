import SwiftUI

struct AdvancedTab: View {
    @State private var hfToken: String = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.hfToken) ?? ""
    @State private var tokenSaved = false

    var body: some View {
        Form {
            Section("HuggingFace") {
                HStack {
                    SecureField("Token HF (opzionale, per download veloci)", text: $hfToken)
                        .textFieldStyle(.roundedBorder)
                    Button("Salva") {
                        if hfToken.isEmpty {
                            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.hfToken)
                        } else {
                            UserDefaults.standard.set(hfToken, forKey: Constants.UserDefaultsKey.hfToken)
                        }
                        tokenSaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            tokenSaved = false
                        }
                    }
                    .disabled(hfToken == UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.hfToken) ?? "")
                }
                if tokenSaved {
                    Text("Token salvato").font(.caption).foregroundColor(.statusOk)
                }
                Text("Senza token: ~500 KB/s. Con token: fino a 50 MB/s.")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text("Crea un token su huggingface.co/settings/tokens (tipo: Read)")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }

            Section("Debug") {
                Text("Accessibilità: \(PreferencesStore.shared.isAccessibilityEnabled ? "OK" : "Non abilitata")")
                Text("Bundle: \(Constants.bundleID)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
