import Foundation
import Cocoa

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    // Cache per evitare decodifica JSON su ogni accesso
    private var _cachedPrompts: [CustomPrompt]?
    private var _cachedPromptsData: Data?

    private var _cachedAppRules: [AppRule]?
    private var _cachedAppRulesData: Data?

    // Cache per isAccessibilityEnabled (osservato via notifica)
    private var _cachedAccessibility: Bool?
    private var _accessibilityObserverRegistered = false

    init() {
        registerAccessibilityObserver()
        seedSecurityExclusions()
    }

    private func seedSecurityExclusions() {
        guard UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) == nil else { return }
        UserDefaults.standard.set(Array(Constants.securityExcludedBundleIDs), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
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

    var isFluencyCheckingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) }
    }

    var fluencyServiceType: ServiceType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.fluencyServiceType),
                  let type = ServiceType(rawValue: raw) else { return .stub }
            return type
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaultsKey.fluencyServiceType) }
    }

    var openAIBaseURL: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIBaseURL) ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.openAIBaseURL) }
    }

    var openAIModel: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openAIModel) ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.openAIModel) }
    }

    var ollamaBaseURL: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaBaseURL) ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.ollamaBaseURL) }
    }

    var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.ollamaModel) ?? "llama3.2" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.ollamaModel) }
    }

    var openRouterAPIKey: String {
        get { (try? KeychainService.shared.load(for: "openrouter")) ?? "" }
        set {
            if newValue.isEmpty {
                try? KeychainService.shared.delete(for: "openrouter")
            } else {
                try? KeychainService.shared.save(key: newValue, for: "openrouter")
            }
        }
    }

    var openRouterModel: String {
        get { UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.openRouterModel) }
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

    var appRules: [AppRule] {
        get {
            let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.appRules)
            if let cached = _cachedAppRules, currentData == _cachedAppRulesData {
                return cached
            }
            guard let data = currentData,
                  let rules = try? JSONDecoder().decode([AppRule].self, from: data) else {
                _cachedAppRules = []
                _cachedAppRulesData = nil
                return []
            }
            _cachedAppRules = rules
            _cachedAppRulesData = data
            return rules
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            _cachedAppRules = newValue
            _cachedAppRulesData = data
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.appRules)
        }
    }

    var isAccessibilityEnabled: Bool {
        if let cached = _cachedAccessibility { return cached }
        let value = AXIsProcessTrusted()
        _cachedAccessibility = value
        return value
    }

    var excludedBundleIDs: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
        }
    }

    func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func addExclusion(_ bundleID: String) {
        var set = excludedBundleIDs
        set.insert(bundleID)
        excludedBundleIDs = set
    }

    func removeExclusion(_ bundleID: String) {
        var set = excludedBundleIDs
        set.remove(bundleID)
        excludedBundleIDs = set
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

    func addAppRule(_ rule: AppRule) {
        var rules = appRules
        rules.append(rule)
        appRules = rules
    }

    func updateAppRule(_ rule: AppRule) {
        var rules = appRules
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            appRules = rules
        }
    }

    func deleteAppRule(_ rule: AppRule) {
        var rules = appRules
        rules.removeAll { $0.id == rule.id }
        appRules = rules
    }
}
