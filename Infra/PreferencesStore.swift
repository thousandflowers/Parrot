import Foundation
import os

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let cache = PreferencesCache()
    /// Trigger per notificare @Observable dei cambiamenti a computed property
    private var _observationTrigger: Int = 0

    init() {
        cache.registerAccessibilityObserver()
        SeedDataProvider.seedSecurityExclusions()
        SeedDataProvider.seedDefaults(preferences: self)
    }

    // MARK: - Language & Style

    var selectedModelID: String { get { string(Constants.UserDefaultsKey.selectedModelID) } set { set(newValue, for: Constants.UserDefaultsKey.selectedModelID) } }
    var language: String { get { string(Constants.UserDefaultsKey.language, fallback: localeDefaultLanguage()) } set { set(newValue, for: Constants.UserDefaultsKey.language) } }
    var style: String { get { string(Constants.UserDefaultsKey.style, fallback: "equilibrato") } set { set(newValue, for: Constants.UserDefaultsKey.style) } }

    // MARK: - Service Configuration

    var serviceType: ServiceType { get { service(Constants.UserDefaultsKey.serviceType) } set { set(newValue, for: Constants.UserDefaultsKey.serviceType) } }

    // MARK: - Fluency

    var autoCheckEnabled: Bool { get { bool(Constants.UserDefaultsKey.autoCheckEnabled) } set { set(newValue, for: Constants.UserDefaultsKey.autoCheckEnabled) } }
    var isFluencyCheckingEnabled: Bool { get { bool(Constants.UserDefaultsKey.isFluencyCheckingEnabled) } set { set(newValue, for: Constants.UserDefaultsKey.isFluencyCheckingEnabled) } }
    var realtimeEnabled: Bool {
        get { bool(Constants.UserDefaultsKey.realtimeEnabled) }
        set {
            set(newValue, for: Constants.UserDefaultsKey.realtimeEnabled)
            if newValue { Task { await RealtimeMonitor.shared.start() } }
            else { Task { await RealtimeMonitor.shared.stop() } }
        }
    }
    var fluencyServiceType: ServiceType { get { service(Constants.UserDefaultsKey.fluencyServiceType) } set { set(newValue, for: Constants.UserDefaultsKey.fluencyServiceType) } }

    // MARK: - OpenAI / Remote

    var openAIBaseURL: String { get { string(Constants.UserDefaultsKey.openAIBaseURL, fallback: "https://api.openai.com/v1") } set { set(newValue, for: Constants.UserDefaultsKey.openAIBaseURL) } }
    var openAIModel: String { get { string(Constants.UserDefaultsKey.openAIModel, fallback: "gpt-4o-mini") } set { set(newValue, for: Constants.UserDefaultsKey.openAIModel) } }

    // MARK: - Ollama / OpenRouter

    var ollamaBaseURL: String { get { string(Constants.UserDefaultsKey.ollamaBaseURL, fallback: "http://localhost:11434") } set { set(newValue, for: Constants.UserDefaultsKey.ollamaBaseURL) } }
    var ollamaModel: String { get { string(Constants.UserDefaultsKey.ollamaModel, fallback: "llama3.2") } set { set(newValue, for: Constants.UserDefaultsKey.ollamaModel) } }
    var openRouterAPIKey: String {
        get {
            observe()
            return (try? KeychainService.shared.load(for: "openrouter")) ?? ""
        }
        set {
            if newValue.isEmpty {
                do { try KeychainService.shared.delete(for: "openrouter") }
                catch { os_log(.error, "PreferencesStore: failed to delete OpenRouter key: %{public}@", error.localizedDescription) }
            } else {
                do { try KeychainService.shared.save(key: newValue, for: "openrouter") }
                catch { os_log(.error, "PreferencesStore: failed to save OpenRouter key: %{public}@", error.localizedDescription) }
            }
            invalidate()
        }
    }
    var openRouterModel: String { get { string(Constants.UserDefaultsKey.openRouterModel, fallback: "openai/gpt-4o-mini") } set { set(newValue, for: Constants.UserDefaultsKey.openRouterModel) } }

    // MARK: - Custom Prompts & App Rules

    var customPrompts: [CustomPrompt] { get { observe(); return cache.customPrompts() } set { if cache.setCustomPrompts(newValue) { invalidate() } } }
    var appRules: [AppRule] { get { observe(); return cache.appRules() } set { if cache.setAppRules(newValue) { invalidate() } } }

    // MARK: - Accessibility & Exclusions

    var isAccessibilityEnabled: Bool { cache.isAccessibilityEnabled }
    var excludedBundleIDs: Set<String> {
        get {
            observe()
            return Set(UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
            invalidate()
        }
    }

    func isExcluded(bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }
    func addExclusion(_ bundleID: String) { var set = excludedBundleIDs; set.insert(bundleID); excludedBundleIDs = set }
    func removeExclusion(_ bundleID: String) { var set = excludedBundleIDs; set.remove(bundleID); excludedBundleIDs = set }
    func cleanup() { cache.cleanup() }

    // MARK: - Mutations

    func addCustomPrompt(_ prompt: CustomPrompt) { var prompts = customPrompts; prompts.append(prompt); customPrompts = prompts }
    func updateCustomPrompt(_ prompt: CustomPrompt) { update(&customPrompts, with: prompt) { $0.id == prompt.id } }
    func deleteCustomPrompt(_ prompt: CustomPrompt) { customPrompts.removeAll { $0.id == prompt.id } }
    func addAppRule(_ rule: AppRule) { var rules = appRules; rules.append(rule); appRules = rules }
    func updateAppRule(_ rule: AppRule) { update(&appRules, with: rule) { $0.id == rule.id } }
    func deleteAppRule(_ rule: AppRule) { appRules.removeAll { $0.id == rule.id } }

    private func string(_ key: String, fallback: String = "") -> String {
        observe()
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }

    private func bool(_ key: String) -> Bool {
        observe()
        return UserDefaults.standard.bool(forKey: key)
    }

    private func service(_ key: String) -> ServiceType {
        observe()
        guard let raw = UserDefaults.standard.string(forKey: key), let type = ServiceType(rawValue: raw) else { return .stub }
        return type
    }

    private func set(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        invalidate()
    }

    private func set(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        invalidate()
    }

    private func set(_ value: ServiceType, for key: String) {
        UserDefaults.standard.set(value.rawValue, forKey: key)
        invalidate()
    }

    private func update<T>(_ values: inout [T], with value: T, matching predicate: (T) -> Bool) {
        if let idx = values.firstIndex(where: predicate) { values[idx] = value }
    }

    private func observe() { _ = _observationTrigger }
    private func invalidate() { _observationTrigger &+= 1 }
    private func localeDefaultLanguage() -> String { Locale.current.language.languageCode?.identifier ?? "en" }
}
