import Foundation
import Cocoa
import os

// MARK: - PreferencesStore
// All UI-critical properties are stored (not computed) so @Observable can track
// them and SwiftUI re-renders views when they change.

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    // MARK: - Stored + Observable properties (persist on didSet)

    var serviceType: ServiceType {
        didSet { UserDefaults.standard.set(serviceType.rawValue, forKey: Constants.UserDefaultsKey.serviceType) }
    }
    var fluencyServiceType: ServiceType {
        didSet { UserDefaults.standard.set(fluencyServiceType.rawValue, forKey: Constants.UserDefaultsKey.fluencyServiceType) }
    }
    var grammarServiceType: ServiceType {
        didSet { UserDefaults.standard.set(grammarServiceType.rawValue, forKey: Constants.UserDefaultsKey.grammarServiceType) }
    }
    var explainServiceType: ServiceType {
        didSet { UserDefaults.standard.set(explainServiceType.rawValue, forKey: Constants.UserDefaultsKey.explainServiceType) }
    }
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Constants.UserDefaultsKey.language) }
    }
    var style: String {
        didSet { UserDefaults.standard.set(style, forKey: Constants.UserDefaultsKey.style) }
    }
    var realtimeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(realtimeEnabled, forKey: Constants.UserDefaultsKey.realtimeEnabled)
            realtimeToggleTask?.cancel()
            realtimeToggleTask = Task {
                if realtimeEnabled { await RealtimeMonitor.shared.start() }
                else               { await RealtimeMonitor.shared.stop()  }
            }
        }
    }
    var lightweightMode: Bool {
        didSet { UserDefaults.standard.set(lightweightMode, forKey: Constants.UserDefaultsKey.lightweightMode) }
    }
    var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Constants.UserDefaultsKey.selectedModelID) }
    }
    var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: Constants.UserDefaultsKey.openAIBaseURL) }
    }
    var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Constants.UserDefaultsKey.openAIModel) }
    }
    var ollamaBaseURL: String {
        didSet { UserDefaults.standard.set(ollamaBaseURL, forKey: Constants.UserDefaultsKey.ollamaBaseURL) }
    }
    var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Constants.UserDefaultsKey.ollamaModel) }
    }
    var openRouterModel: String {
        didSet { UserDefaults.standard.set(openRouterModel, forKey: Constants.UserDefaultsKey.openRouterModel) }
    }
    var shortcutGrammar: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutGrammar) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutGrammar) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutFluency: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutFluency) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutFluency) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutEditor: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutEditor) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutEditor) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutReplace: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutReplace) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutReplace) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutTranslate: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutTranslate) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutTranslate) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutApplyDirect: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutApplyDirect) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutApplyDirect) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var shortcutCoach: ShortcutConfig {
        didSet {
            if let d = try? JSONEncoder().encode(shortcutCoach) { UserDefaults.standard.set(d, forKey: Constants.UserDefaultsKey.shortcutCoach) }
            GlobalHotkeyManager.current?.updateHotkeys()
        }
    }
    var translationLanguage: String {
        didSet { UserDefaults.standard.set(translationLanguage, forKey: Constants.UserDefaultsKey.translationLanguage) }
    }

    // MARK: - Accessibility (stored so @Observable notifies the UI)

    var accessibilityEnabled: Bool = false

    // MARK: - Cache for complex computed properties

    private var _cachedPrompts: [CustomPrompt]?
    private var _cachedPromptsData: Data?
    private var _cachedAppRules: [AppRule]?
    private var _cachedAppRulesData: Data?
    private var _accessibilityObserverRegistered = false
    private var realtimeToggleTask: Task<Void, Never>?
    private var accessibilityPollTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        let hasModel = PreferencesStore.hasDownloadedModels()

        serviceType = ServiceType(rawValue: ud.string(forKey: Constants.UserDefaultsKey.serviceType) ?? "")
            ?? (hasModel ? .local : .stub)
        fluencyServiceType = ServiceType(rawValue: ud.string(forKey: Constants.UserDefaultsKey.fluencyServiceType) ?? "")
            ?? (hasModel ? .local : .stub)
        grammarServiceType = ServiceType(rawValue: ud.string(forKey: Constants.UserDefaultsKey.grammarServiceType) ?? "")
            ?? (hasModel ? .local : .stub)
        explainServiceType = ServiceType(rawValue: ud.string(forKey: Constants.UserDefaultsKey.explainServiceType) ?? "")
            ?? (hasModel ? .local : .stub)
        language   = ud.string(forKey: Constants.UserDefaultsKey.language) ?? PreferencesStore.localeDefault()
        style      = ud.string(forKey: Constants.UserDefaultsKey.style) ?? "equilibrato"
        realtimeEnabled = ud.bool(forKey: Constants.UserDefaultsKey.realtimeEnabled)
        lightweightMode = ud.bool(forKey: Constants.UserDefaultsKey.lightweightMode)
        selectedModelID = ud.string(forKey: Constants.UserDefaultsKey.selectedModelID) ?? ""
        openAIBaseURL   = ud.string(forKey: Constants.UserDefaultsKey.openAIBaseURL)   ?? "https://api.openai.com/v1"
        openAIModel     = ud.string(forKey: Constants.UserDefaultsKey.openAIModel)     ?? "gpt-4o-mini"
        ollamaBaseURL   = ud.string(forKey: Constants.UserDefaultsKey.ollamaBaseURL)   ?? "http://localhost:11434"
        ollamaModel     = ud.string(forKey: Constants.UserDefaultsKey.ollamaModel)     ?? "llama3.2"
        openRouterModel = ud.string(forKey: Constants.UserDefaultsKey.openRouterModel) ?? "openai/gpt-4o-mini"
        shortcutGrammar = (ud.data(forKey: Constants.UserDefaultsKey.shortcutGrammar).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .grammarDefault
        shortcutFluency = (ud.data(forKey: Constants.UserDefaultsKey.shortcutFluency).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .fluencyDefault
        shortcutEditor  = (ud.data(forKey: Constants.UserDefaultsKey.shortcutEditor).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .editorDefault
        shortcutReplace  = (ud.data(forKey: Constants.UserDefaultsKey.shortcutReplace).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .replaceDefault
        shortcutTranslate = (ud.data(forKey: Constants.UserDefaultsKey.shortcutTranslate).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .translateDefault
        shortcutApplyDirect = (ud.data(forKey: Constants.UserDefaultsKey.shortcutApplyDirect).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .applyDirectDefault
        shortcutCoach = (ud.data(forKey: Constants.UserDefaultsKey.shortcutCoach).flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }) ?? .coachDefault
        translationLanguage = ud.string(forKey: Constants.UserDefaultsKey.translationLanguage) ?? "en"

        // If local service is stored but llama-server is absent, fall back to stub silently.
        let llamaFound = ModelManager.shared.resolvedLlamaServerURL() != nil
        if serviceType == .local && !llamaFound {
            serviceType = .stub
            ud.set(ServiceType.stub.rawValue, forKey: Constants.UserDefaultsKey.serviceType)
        }
        if fluencyServiceType == .local && !llamaFound {
            fluencyServiceType = .stub
            ud.set(ServiceType.stub.rawValue, forKey: Constants.UserDefaultsKey.fluencyServiceType)
        }

        // Prompt the system dialog if not yet trusted; use real AX probe for reliability.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        accessibilityEnabled = PreferencesStore.probeAccessibility()
        registerAccessibilityObserver()
        seedSecurityExclusions()
        startAccessibilityPolling()
    }

    // MARK: - OpenRouter API key (Keychain — not stored in memory)

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

    // MARK: - Presets

    var presets: [Preset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "presets"),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let encoded = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(encoded, forKey: "presets")
        }
    }
    func addPreset(_ preset: Preset) { var p = presets; p.append(preset); presets = p }
    func updatePreset(_ preset: Preset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) { presets[i] = preset }
    }
    func deletePreset(_ preset: Preset) { presets.removeAll { $0.id == preset.id } }

    // MARK: - Custom Prompts

    var customPrompts: [CustomPrompt] {
        get {
            let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.customPrompts)
            if let cached = _cachedPrompts, data == _cachedPromptsData { return cached }
            guard let d = data, let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: d) else {
                _cachedPrompts = []; _cachedPromptsData = nil; return []
            }
            _cachedPrompts = prompts; _cachedPromptsData = d; return prompts
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            _cachedPrompts = newValue; _cachedPromptsData = data
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.customPrompts)
        }
    }

    // MARK: - App Rules

    var appRules: [AppRule] {
        get {
            let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.appRules)
            if let cached = _cachedAppRules, data == _cachedAppRulesData { return cached }
            guard let d = data, let rules = try? JSONDecoder().decode([AppRule].self, from: d) else {
                _cachedAppRules = []; _cachedAppRulesData = nil; return []
            }
            _cachedAppRules = rules; _cachedAppRulesData = d; return rules
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            _cachedAppRules = newValue; _cachedAppRulesData = data
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.appRules)
        }
    }

    // MARK: - Exclusions

    var excludedBundleIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.excludedBundleIDs) }
    }

    func isExcluded(bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }

    // MARK: - User Dictionary

    var userDictionaryWords: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.userDictionaryWords) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.userDictionaryWords)
        }
    }
    func addWordToDictionary(_ word: String) { var words = userDictionaryWords; words.insert(word.lowercased()); userDictionaryWords = words }
    func removeWordFromDictionary(_ word: String) { var words = userDictionaryWords; words.remove(word.lowercased()); userDictionaryWords = words }

    // MARK: - Context Window

    var contextWindowSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKey.contextWindowSize)
            return stored > 0 ? stored : 200
        }
        set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKey.contextWindowSize) }
    }
    func addExclusion(_ id: String)    { var s = excludedBundleIDs; s.insert(id);  excludedBundleIDs = s }
    func removeExclusion(_ id: String) { var s = excludedBundleIDs; s.remove(id);  excludedBundleIDs = s }

    // isAccessibilityEnabled kept for code that still references it
    var isAccessibilityEnabled: Bool { accessibilityEnabled }

    // MARK: - Mutations

    func addCustomPrompt(_ p: CustomPrompt)    { customPrompts.append(p) }
    func updateCustomPrompt(_ p: CustomPrompt) {
        if let i = customPrompts.firstIndex(where: { $0.id == p.id }) { customPrompts[i] = p }
    }
    func deleteCustomPrompt(_ p: CustomPrompt) { customPrompts.removeAll { $0.id == p.id } }

    func addAppRule(_ r: AppRule)    { appRules.append(r) }
    func updateAppRule(_ r: AppRule) {
        if let i = appRules.firstIndex(where: { $0.id == r.id }) { appRules[i] = r }
    }
    func deleteAppRule(_ r: AppRule) { appRules.removeAll { $0.id == r.id } }

    func cleanup() { DistributedNotificationCenter.default().removeObserver(self) }

    // MARK: - Private helpers

    private static func hasDownloadedModels() -> Bool {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RefineClone/Models")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
        return contents.contains { $0.hasSuffix(".gguf") }
    }

    private static func localeDefault() -> String {
        Locale.current.language.languageCode?.identifier ?? "it"
    }

    private func seedSecurityExclusions() {
        guard UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) == nil else { return }
        UserDefaults.standard.set(Array(Constants.securityExcludedBundleIDs), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
    }

    /// Uses an actual AX API call to verify trust — more reliable than AXIsProcessTrusted()
    /// alone for ad-hoc and Apple-Development-signed binaries on macOS Sequoia+.
    static func probeAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let systemAX = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemAX, kAXFocusedApplicationAttribute as CFString, &ref
        )
        return result != .apiDisabled
    }

    private func startAccessibilityPolling() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let trusted = PreferencesStore.probeAccessibility()
                if trusted != self.accessibilityEnabled { self.accessibilityEnabled = trusted }
            }
        }
    }

    private func registerAccessibilityObserver() {
        guard !_accessibilityObserverRegistered else { return }
        _accessibilityObserverRegistered = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.accessibilityEnabled = PreferencesStore.probeAccessibility()
            }
        }
    }
}
