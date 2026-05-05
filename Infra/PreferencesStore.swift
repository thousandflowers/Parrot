import Foundation
import Cocoa

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    // Cache per evitare decodifica JSON su ogni accesso
    private var _cachedPrompts: [CustomPrompt]?
    private var _cachedPromptsData: Data?

    // Cache per isAccessibilityEnabled (osservato via notifica)
    private var _cachedAccessibility: Bool?
    private var _accessibilityObserverRegistered = false

    init() {
        registerAccessibilityObserver()
    }

    var selectedModelID: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.selectedModelID) }
    }

    var language: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.language) ?? localeDefaultLanguage() }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.language) }
    }

    var style: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.style) ?? "equilibrato" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.style) }
    }

    var serviceType: ServiceType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.serviceType),
                  let type = ServiceType(rawValue: raw) else { return .stub }
            return type
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.serviceType) }
    }


    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.autoCheckEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.autoCheckEnabled) }
    }

    var openAIBaseURL: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIBaseURL) ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.openAIBaseURL) }
    }

    var openAIModel: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.openAIModel) }
    }


    var customPrompts: [CustomPrompt] {
        get {
            let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.customPrompts)
            if let cached = _cachedPrompts, currentData == _cachedPromptsData {
                return cached
            }
            guard let data = currentData,
                  let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: data) else {
                _cachedPrompts = []
                _cachedPromptsData = nil
                return []
            }
            _cachedPrompts = prompts
            _cachedPromptsData = data
            return prompts
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            _cachedPrompts = newValue
            _cachedPromptsData = data
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.customPrompts)
        }
    }

    var isAccessibilityEnabled: Bool {
        if let cached = _cachedAccessibility { return cached }
        let value = AXIsProcessTrusted()
        _cachedAccessibility = value
        return value
    }

    private func registerAccessibilityObserver() {
        guard !_accessibilityObserverRegistered else { return }
        _accessibilityObserverRegistered = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?._cachedAccessibility = nil // Invalida cache
        }
    }

    private func localeDefaultLanguage() -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return lang
    }

    func addCustomPrompt(_ prompt: CustomPrompt) {
        var prompts = customPrompts
        prompts.append(prompt)
        customPrompts = prompts
    }

    func updateCustomPrompt(_ prompt: CustomPrompt) {
        var prompts = customPrompts
        if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[idx] = prompt
            customPrompts = prompts
        }
    }

    func deleteCustomPrompt(_ prompt: CustomPrompt) {
        var prompts = customPrompts
        prompts.removeAll { $0.id == prompt.id }
        customPrompts = prompts
    }
}
