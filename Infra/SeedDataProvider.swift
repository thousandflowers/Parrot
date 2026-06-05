import Foundation

@MainActor
struct SeedDataProvider {
    static func seedDefaults(preferences: PreferencesStore) {
        let hasModel = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID)?.isEmpty == false
            || !PreferencesCache.downloadedModels().isEmpty
        if UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.serviceType) == nil {
            UserDefaults.standard.set(hasModel ? ServiceType.local.rawValue : ServiceType.stub.rawValue,
                                      forKey: Constants.UserDefaultsKey.serviceType)
        }
        if UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.fluencyServiceType) == nil {
            UserDefaults.standard.set(hasModel ? ServiceType.local.rawValue : ServiceType.stub.rawValue,
                                      forKey: Constants.UserDefaultsKey.fluencyServiceType)
        }
        if UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) == nil {
            UserDefaults.standard.set("it", forKey: Constants.UserDefaultsKey.language)
        }
        // Inline-completion accept key defaults (read from nonisolated C callback, so write them explicitly).
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.completionPartialKeyCode) == nil {
            UserDefaults.standard.set(48, forKey: Constants.UserDefaultsKey.completionPartialKeyCode)
        }
        if UserDefaults.standard.object(forKey: Constants.UserDefaultsKey.completionFullKeyCode) == nil {
            UserDefaults.standard.set(42, forKey: Constants.UserDefaultsKey.completionFullKeyCode)
        }
        seedPromptPresets(preferences: preferences)
    }

    static func seedPromptPresets(preferences: PreferencesStore) {
        guard preferences.customPrompts.isEmpty else { return }
        preferences.customPrompts = [
            CustomPrompt(
                id: UUID(uuidString: "E1E1E1E1-0000-4000-8000-000000000001") ?? UUID(),
                name: "Email Formale",
                template: "Correggi il testo mantenendo un tono formale e professionale. Preserva saluti, firme e formule di cortesia. Non aggiungere emoji o slang.\n\n{{TEXT}}",
                checkType: .grammar
            ),
            CustomPrompt(
                id: UUID(uuidString: "E1E1E1E1-0000-4000-8000-000000000002") ?? UUID(),
                name: "Chat / Messaggi",
                template: "Correggi solo errori grammaticali evidenti. Mantieni il tono informale e conversazionale. Le contrazioni e lo slang leggero sono accettabili.\n\n{{TEXT}}",
                checkType: .grammar
            ),
            CustomPrompt(
                id: UUID(uuidString: "E1E1E1E1-0000-4000-8000-000000000003") ?? UUID(),
                name: "Documento Tecnico",
                template: "Correggi la grammatica preservando TUTTI i termini tecnici, nomi di variabili, snippet di codice, comandi, URL e abbreviazioni. Non modificare la formattazione tecnica.\n\n{{TEXT}}",
                checkType: .grammar
            ),
        ]
    }

    static func seedSecurityExclusions() {
        guard UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) == nil else { return }
        UserDefaults.standard.set(Array(Constants.securityExcludedBundleIDs), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
    }
}
