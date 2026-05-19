import Foundation
import OSLog

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let cache = PreferencesCache()
    private var _cachedAPIKeys: [String: String] = [:]
    /// Trigger per notificare @Observable dei cambiamenti a computed property
    private var _observationTrigger: Int = 0

    init() {
        cache.registerAccessibilityObserver { [weak self] in self?.invalidate() }
        SeedDataProvider.seedSecurityExclusions()
        SeedDataProvider.seedDefaults(preferences: self)
    }

    // MARK: - Core Preferences

    var selectedModelID: String { get { string(Constants.UserDefaultsKey.selectedModelID) } set { set(newValue, for: Constants.UserDefaultsKey.selectedModelID) } }
    var language: String { get { string(Constants.UserDefaultsKey.language, fallback: localeDefaultLanguage()) } set { set(newValue, for: Constants.UserDefaultsKey.language) } }
    var style: String { get { string(Constants.UserDefaultsKey.style, fallback: "equilibrato") } set { set(newValue, for: Constants.UserDefaultsKey.style) } }
    var serviceType: ServiceType { get { service(Constants.UserDefaultsKey.serviceType) } set { set(newValue, for: Constants.UserDefaultsKey.serviceType) } }

    var autoCheckEnabled: Bool { get { bool(Constants.UserDefaultsKey.autoCheckEnabled) } set { set(newValue, for: Constants.UserDefaultsKey.autoCheckEnabled) } }
    var realtimeEnabled: Bool {
        get { bool(Constants.UserDefaultsKey.realtimeEnabled) }
        set {
            set(newValue, for: Constants.UserDefaultsKey.realtimeEnabled)
            if newValue {
                Task { await RealtimeMonitor.shared.start() }
            } else {
                Task { await RealtimeMonitor.shared.stop() }
            }
        }
    }

    // MARK: - OpenAI / Remote

    var openAIBaseURL: String { get { string(Constants.UserDefaultsKey.openAIBaseURL, fallback: "https://api.openai.com/v1") } set { set(newValue, for: Constants.UserDefaultsKey.openAIBaseURL) } }
    var openAIModel: String { get { string(Constants.UserDefaultsKey.openAIModel, fallback: "gpt-4o-mini") } set { set(newValue, for: Constants.UserDefaultsKey.openAIModel) } }
    var openAIAPIKey: String {
        get {
            observe()
            if let cached = _cachedAPIKeys["openai"] { return cached }
            let key = (try? KeychainService.shared.load(for: "openai")) ?? ""
            _cachedAPIKeys["openai"] = key
            return key
        }
        set {
            if newValue.isEmpty {
                do { try KeychainService.shared.delete(for: "openai") }
                catch { Logger.infra.error("PreferencesStore: failed to delete OpenAI key: \(error.localizedDescription, privacy: .public)") }
                _cachedAPIKeys.removeValue(forKey: "openai")
            } else {
                do { try KeychainService.shared.save(key: newValue, for: "openai") }
                catch { Logger.infra.error("PreferencesStore: failed to save OpenAI key: \(error.localizedDescription, privacy: .public)") }
                _cachedAPIKeys["openai"] = newValue
            }
            invalidate()
        }
    }

    // MARK: - Ollama / OpenRouter

    var ollamaBaseURL: String { get { string(Constants.UserDefaultsKey.ollamaBaseURL, fallback: "http://localhost:11434") } set { set(newValue, for: Constants.UserDefaultsKey.ollamaBaseURL) } }
    var ollamaModel: String { get { string(Constants.UserDefaultsKey.ollamaModel, fallback: "llama3.2") } set { set(newValue, for: Constants.UserDefaultsKey.ollamaModel) } }
    var openRouterAPIKey: String {
        get {
            observe()
            if let cached = _cachedAPIKeys["openrouter"] { return cached }
            let key = (try? KeychainService.shared.load(for: "openrouter")) ?? ""
            _cachedAPIKeys["openrouter"] = key
            return key
        }
        set {
            if newValue.isEmpty {
                do { try KeychainService.shared.delete(for: "openrouter") }
                catch { Logger.infra.error("PreferencesStore: failed to delete OpenRouter key: \(error.localizedDescription, privacy: .public)") }
                _cachedAPIKeys.removeValue(forKey: "openrouter")
            } else {
                do { try KeychainService.shared.save(key: newValue, for: "openrouter") }
                catch { Logger.infra.error("PreferencesStore: failed to save OpenRouter key: \(error.localizedDescription, privacy: .public)") }
                _cachedAPIKeys["openrouter"] = newValue
            }
            invalidate()
        }
    }
    var openRouterModel: String { get { string(Constants.UserDefaultsKey.openRouterModel, fallback: "openai/gpt-4o-mini") } set { set(newValue, for: Constants.UserDefaultsKey.openRouterModel) } }
    var translationLanguage: String { get { string(Constants.UserDefaultsKey.translationLanguage, fallback: "en") } set { set(newValue, for: Constants.UserDefaultsKey.translationLanguage) } }

    // MARK: - Shortcuts

    var shortcutGrammar: ShortcutConfig    { get { shortcut(Constants.UserDefaultsKey.shortcutGrammar, fallback: .grammarDefault) }    set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutGrammar) } }
    var shortcutFluency: ShortcutConfig    { get { shortcut(Constants.UserDefaultsKey.shortcutFluency, fallback: .fluencyDefault) }    set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutFluency) } }
    var shortcutEditor: ShortcutConfig     { get { shortcut(Constants.UserDefaultsKey.shortcutEditor, fallback: .editorDefault) }      set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutEditor) } }
    var shortcutReplace: ShortcutConfig    { get { shortcut(Constants.UserDefaultsKey.shortcutReplace, fallback: .replaceDefault) }    set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutReplace) } }
    var shortcutTranslate: ShortcutConfig  { get { shortcut(Constants.UserDefaultsKey.shortcutTranslate, fallback: .translateDefault) } set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutTranslate) } }
    var shortcutApplyDirect: ShortcutConfig { get { shortcut(Constants.UserDefaultsKey.shortcutApplyDirect, fallback: .applyDirectDefault) } set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutApplyDirect) } }
    var shortcutCoach: ShortcutConfig      { get { shortcut(Constants.UserDefaultsKey.shortcutCoach, fallback: .coachDefault) }        set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutCoach) } }
    var shortcutApplyAll: ShortcutConfig   { get { shortcut(Constants.UserDefaultsKey.shortcutApplyAll, fallback: .applyAllDefault) }  set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutApplyAll) } }
    var shortcutGrammarFluency: ShortcutConfig { get { shortcut(Constants.UserDefaultsKey.shortcutGrammarFluency, fallback: .grammarFluencyDefault) } set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutGrammarFluency) } }

    // MARK: - Presets

    var presets: [Preset] {
        get {
            observe()
            guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.presets),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.presets)
            invalidate()
        }
    }

    func addPreset(_ preset: Preset) { var p = presets; p.append(preset); presets = p }
    func updatePreset(_ preset: Preset) { update(&presets, with: preset) { $0.id == preset.id } }
    func deletePreset(_ preset: Preset) { presets.removeAll { $0.id == preset.id } }

    // MARK: - Custom Prompts & App Rules

    var customPrompts: [CustomPrompt] { get { observe(); return cache.customPrompts() } set { if cache.setCustomPrompts(newValue) { invalidate() } } }
    var appRules: [AppRule] { get { observe(); return cache.appRules() } set { if cache.setAppRules(newValue) { invalidate() } } }

    // MARK: - Accessibility & Exclusions

    var isAccessibilityEnabled: Bool { observe(); return cache.isAccessibilityEnabled }

    func refreshAccessibility() {
        cache.invalidateAccessibility()
        invalidate()
    }
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

    private func shortcut(_ key: String, fallback: ShortcutConfig) -> ShortcutConfig {
        observe()
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else { return fallback }
        return decoded
    }

    private func setShortcut(_ value: ShortcutConfig, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        invalidate()
    }

    private func update<T>(_ values: inout [T], with value: T, matching predicate: (T) -> Bool) {
        if let idx = values.firstIndex(where: predicate) { values[idx] = value }
    }

    private func observe() { _ = _observationTrigger }
    private func invalidate() { _observationTrigger &+= 1 }
    private func localeDefaultLanguage() -> String { Locale.current.language.languageCode?.identifier ?? "en" }
}
