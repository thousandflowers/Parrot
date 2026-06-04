import Foundation
import OSLog

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let cache = PreferencesCache()
    private var _cachedAPIKeys: [String: String] = [:]
    private var realtimeTask: Task<Void, Never>?
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
            realtimeTask?.cancel()
            if newValue {
                realtimeTask = Task { await RealtimeMonitor.shared.start() }
            } else {
                realtimeTask = Task { await RealtimeMonitor.shared.stop() }
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

    // MARK: - Model Fallback

    var fallbackLocalModelID: String { get { string(Constants.UserDefaultsKey.fallbackLocalModelID, fallback: "") } set { set(newValue, for: Constants.UserDefaultsKey.fallbackLocalModelID) } }
    var fallbackOpenAIModel: String { get { string(Constants.UserDefaultsKey.fallbackOpenAIModel, fallback: "") } set { set(newValue, for: Constants.UserDefaultsKey.fallbackOpenAIModel) } }
    var fallbackOllamaModel: String { get { string(Constants.UserDefaultsKey.fallbackOllamaModel, fallback: "") } set { set(newValue, for: Constants.UserDefaultsKey.fallbackOllamaModel) } }
    var fallbackOpenRouterModel: String { get { string(Constants.UserDefaultsKey.fallbackOpenRouterModel, fallback: "") } set { set(newValue, for: Constants.UserDefaultsKey.fallbackOpenRouterModel) } }

    // MARK: - Inline Annotations

    var inlineAnnotationsHoverOnly: Bool { get { bool(Constants.UserDefaultsKey.inlineAnnotationsHoverOnly) } set { set(newValue, for: Constants.UserDefaultsKey.inlineAnnotationsHoverOnly) } }
    var aiPromptAutoDetect: Bool { get { bool(Constants.UserDefaultsKey.aiPromptAutoDetect) } set { set(newValue, for: Constants.UserDefaultsKey.aiPromptAutoDetect) } }

    var treeTraversalDisabledBundleIDs: Set<String> {
        get {
            observe()
            return Set(UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.treeTraversalDisabledBundleIDs) ?? [])
        }
        set {
            let current = Set(UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.treeTraversalDisabledBundleIDs) ?? [])
            if current != newValue {
                UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.treeTraversalDisabledBundleIDs)
                invalidate()
            }
        }
    }

    func isTreeTraversalDisabled(bundleID: String) -> Bool { treeTraversalDisabledBundleIDs.contains(bundleID) }
    func disableTreeTraversal(_ bundleID: String) { var s = treeTraversalDisabledBundleIDs; s.insert(bundleID); treeTraversalDisabledBundleIDs = s }
    func enableTreeTraversal(_ bundleID: String) { var s = treeTraversalDisabledBundleIDs; s.remove(bundleID); treeTraversalDisabledBundleIDs = s }

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
    var shortcutDeSlop: ShortcutConfig { get { shortcut(Constants.UserDefaultsKey.shortcutDeSlop, fallback: .deSlopDefault) } set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutDeSlop) } }
    var shortcutAIPrompt: ShortcutConfig { get { shortcut(Constants.UserDefaultsKey.shortcutAIPrompt, fallback: .aiPromptDefault) } set { setShortcut(newValue, for: Constants.UserDefaultsKey.shortcutAIPrompt) } }

    // MARK: - Presets

    var presets: [Preset] {
        get {
            observe()
            guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.presets),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let newData = try? JSONEncoder().encode(newValue) else {
                Logger.infra.warning("PreferencesStore: failed to encode presets")
                return
            }
            let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.presets)
            if currentData != newData {
                UserDefaults.standard.set(newData, forKey: Constants.UserDefaultsKey.presets)
                invalidate()
            }
        }
    }

    func addPreset(_ preset: Preset) { var p = presets; p.append(preset); presets = p }
    func updatePreset(_ preset: Preset) { update(&presets, with: preset) { $0.id == preset.id } }
    func deletePreset(_ preset: Preset) { presets.removeAll { $0.id == preset.id } }

    // MARK: - Flows

    var flows: [Flow] {
        get {
            observe()
            guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.flows),
                  let decoded = try? JSONDecoder().decode([Flow].self, from: data) else { return defaultFlows }
            return decoded.isEmpty ? defaultFlows : decoded
        }
        set {
            guard let newData = try? JSONEncoder().encode(newValue) else {
                Logger.infra.warning("PreferencesStore: failed to encode flows")
                return
            }
            let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.flows)
            if currentData != newData {
                UserDefaults.standard.set(newData, forKey: Constants.UserDefaultsKey.flows)
                invalidate()
            }
        }
    }

    private var defaultFlows: [Flow] {
        [
            Flow(name: "Grammar + Fluency", steps: [
                .init(promptType: .grammar),
                .init(promptType: .fluency),
            ]),
            Flow(name: "Formal Polish", steps: [
                .init(promptType: .grammar),
                .init(promptType: .custom(name: "Formal", template: "Make the text more formal and professional.")),
            ]),
        ]
    }

    func addFlow(_ flow: Flow) { var f = flows; f.append(flow); flows = f }
    func updateFlow(_ flow: Flow) { update(&flows, with: flow) { $0.id == flow.id } }
    func deleteFlow(_ flow: Flow) { flows.removeAll { $0.id == flow.id } }

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
            let current = Set(UserDefaults.standard.stringArray(forKey: Constants.UserDefaultsKey.excludedBundleIDs) ?? [])
            if current != newValue {
                UserDefaults.standard.set(Array(newValue), forKey: Constants.UserDefaultsKey.excludedBundleIDs)
                invalidate()
            }
        }
    }

    func isExcluded(bundleID: String) -> Bool { excludedBundleIDs.contains(bundleID) }
    func addExclusion(_ bundleID: String) { var set = excludedBundleIDs; set.insert(bundleID); excludedBundleIDs = set }
    func removeExclusion(_ bundleID: String) { var set = excludedBundleIDs; set.remove(bundleID); excludedBundleIDs = set }
    func cleanup() { cache.cleanup() }

    // MARK: - Snapshot (Sendable capture for background use)

    struct Snapshot: Sendable {
        let customPrompts: [CustomPrompt]
        let appRules: [AppRule]
        let excludedBundleIDs: Set<String>
        let translationLanguage: String
        let serviceType: ServiceType
        let openAIModel: String
        let ollamaModel: String
        let openRouterModel: String
        let selectedModelID: String
        let language: String
        let style: String
    }

    func snapshot() -> Snapshot {
        Snapshot(
            customPrompts: cache.customPrompts(),
            appRules: cache.appRules(),
            excludedBundleIDs: excludedBundleIDs,
            translationLanguage: translationLanguage,
            serviceType: serviceType,
            openAIModel: openAIModel,
            ollamaModel: ollamaModel,
            openRouterModel: openRouterModel,
            selectedModelID: selectedModelID,
            language: language,
            style: style
        )
    }

    // MARK: - Mutations

    func addCustomPrompt(_ prompt: CustomPrompt) { var prompts = customPrompts; prompts.append(prompt); customPrompts = prompts }
    func updateCustomPrompt(_ prompt: CustomPrompt) { update(&customPrompts, with: prompt) { $0.id == prompt.id } }
    func deleteCustomPrompt(_ prompt: CustomPrompt) { customPrompts.removeAll { $0.id == prompt.id } }
    func addAppRule(_ rule: AppRule) { var rules = appRules; rules.append(rule); appRules = rules }
    func updateAppRule(_ rule: AppRule) { update(&appRules, with: rule) { $0.id == rule.id } }
    func deleteAppRule(_ rule: AppRule) { appRules.removeAll { $0.id == rule.id } }

    // MARK: - Inline completion (SP1)
    var inlineCompletionEnabled: Bool {
        get { bool(Constants.UserDefaultsKey.inlineCompletionEnabled, default: true) }
        set { set(newValue, for: Constants.UserDefaultsKey.inlineCompletionEnabled) }
    }
    var maxCompletionLength: Int {
        get { int(Constants.UserDefaultsKey.maxCompletionLength, fallback: Constants.completionDefaultMaxWords) }
        set { set(newValue, for: Constants.UserDefaultsKey.maxCompletionLength) }
    }
    var completionDebounceMs: Int {
        get { int(Constants.UserDefaultsKey.completionDebounceMs, fallback: Constants.completionDefaultDebounceMs) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionDebounceMs) }
    }
    /// Use OCR of the conversation/email above the caret as extra completion context (Wren).
    /// Defaults on; no-ops without Screen Recording permission.
    var completionScreenContextEnabled: Bool {
        get { bool(Constants.UserDefaultsKey.completionScreenContextEnabled, default: true) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionScreenContextEnabled) }
    }
    var completionUserPrompt: String {
        get { string(Constants.UserDefaultsKey.completionUserPrompt, fallback: "") }
        set { set(newValue, for: Constants.UserDefaultsKey.completionUserPrompt) }
    }
    /// Empty = use the same model as correction (single server). Non-empty = dedicated completion model.
    var completionModelID: String {
        get { string(Constants.UserDefaultsKey.completionModelID, fallback: "") }
        set { set(newValue, for: Constants.UserDefaultsKey.completionModelID) }
    }
    var completionUseAppContext: Bool {
        get { bool(Constants.UserDefaultsKey.completionUseAppContext, default: true) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionUseAppContext) }
    }
    var completionUseScreenContext: Bool {
        get { bool(Constants.UserDefaultsKey.completionUseScreenContext, default: false) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionUseScreenContext) }
    }
    var completionUseClipboardContext: Bool {
        get { bool(Constants.UserDefaultsKey.completionUseClipboardContext, default: false) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionUseClipboardContext) }
    }
    var completionEmojiSkinTone: Int {
        get { int(Constants.UserDefaultsKey.completionEmojiSkinTone, fallback: 0) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionEmojiSkinTone) }
    }

    var personalizationStrength: Double {
        get { double(Constants.UserDefaultsKey.personalizationStrength, fallback: 0.5) }
        set { set(newValue, for: Constants.UserDefaultsKey.personalizationStrength) }
    }
    var personalizationInstructions: String {
        get { string(Constants.UserDefaultsKey.personalizationInstructions, fallback: "") }
        set { set(newValue, for: Constants.UserDefaultsKey.personalizationInstructions) }
    }

    var completionOverlayFontSize: Double {
        get { double(Constants.UserDefaultsKey.completionOverlayFontSize, fallback: 0.0) }
        set { set(newValue, for: Constants.UserDefaultsKey.completionOverlayFontSize) }
    }

    // MARK: - Snippets

    var snippets: [Snippet] {
        get {
            observe()
            guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.snippets),
                  let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else { return [] }
            return decoded
        }
        set {
            guard let newData = try? JSONEncoder().encode(newValue) else {
                Logger.infra.warning("PreferencesStore: failed to encode snippets")
                return
            }
            let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.snippets)
            if currentData != newData {
                UserDefaults.standard.set(newData, forKey: Constants.UserDefaultsKey.snippets)
                invalidate()
            }
        }
    }

    func addSnippet(_ snippet: Snippet) { var s = snippets; s.append(snippet); snippets = s }
    func updateSnippet(_ snippet: Snippet) { update(&snippets, with: snippet) { $0.id == snippet.id } }
    func deleteSnippet(_ snippet: Snippet) { snippets.removeAll { $0.id == snippet.id } }

    private func string(_ key: String, fallback: String = "") -> String {
        observe()
        return UserDefaults.standard.string(forKey: key) ?? fallback
    }

    private func bool(_ key: String) -> Bool {
        observe()
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Bool with an explicit default used when the key was never set (UserDefaults.bool is false otherwise).
    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        observe()
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func int(_ key: String, fallback: Int) -> Int {
        observe()
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.integer(forKey: key)
    }

    private func set(_ value: Int, for key: String) {
        let current = UserDefaults.standard.object(forKey: key) as? Int
        UserDefaults.standard.set(value, forKey: key)
        if current != value { invalidate() }
    }

    private func service(_ key: String) -> ServiceType {
        observe()
        guard let raw = UserDefaults.standard.string(forKey: key), let type = ServiceType(rawValue: raw) else { return .local }
        return type
    }

    private func set(_ value: String, for key: String) {
        let current = UserDefaults.standard.string(forKey: key) ?? ""
        UserDefaults.standard.set(value, forKey: key)
        if current != value { invalidate() }
    }

    private func double(_ key: String, fallback: Double) -> Double {
        observe()
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.double(forKey: key)
    }

    private func set(_ value: Bool, for key: String) {
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        if current != value { invalidate() }
    }

    private func set(_ value: Double, for key: String) {
        let current = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        if current != value { invalidate() }
    }

    private func set(_ value: ServiceType, for key: String) {
        let currentRaw = UserDefaults.standard.string(forKey: key) ?? ""
        UserDefaults.standard.set(value.rawValue, forKey: key)
        if currentRaw != value.rawValue { invalidate() }
    }

    private func shortcut(_ key: String, fallback: ShortcutConfig) -> ShortcutConfig {
        observe()
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else { return fallback }
        return decoded
    }

    private func setShortcut(_ value: ShortcutConfig, for key: String) {
        let currentData = UserDefaults.standard.data(forKey: key)
        guard let data = try? JSONEncoder().encode(value) else {
            Logger.infra.warning("PreferencesStore: failed to encode shortcut for \(key, privacy: .public)")
            return
        }
        if currentData != data {
            UserDefaults.standard.set(data, forKey: key)
            invalidate()
        }
    }

    private func update<T>(_ values: inout [T], with value: T, matching predicate: (T) -> Bool) {
        if let idx = values.firstIndex(where: predicate) { values[idx] = value }
    }

    private func observe() { _ = _observationTrigger }
    private func invalidate() { _observationTrigger &+= 1 }
    private func localeDefaultLanguage() -> String { Locale.current.language.languageCode?.identifier ?? "en" }
}
