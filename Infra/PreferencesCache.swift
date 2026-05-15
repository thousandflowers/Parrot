import Cocoa
import Foundation
import OSLog

@MainActor
final class PreferencesCache {
    private var cachedPrompts: [CustomPrompt]?
    private var cachedPromptsData: Data?
    private var cachedAppRules: [AppRule]?
    private var cachedAppRulesData: Data?
    private var cachedAccessibility: Bool?
    private var cachedAccessibilityTimestamp: Date = .distantPast
    private var accessibilityObserver: NSObjectProtocol?

    func customPrompts() -> [CustomPrompt] {
        let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.customPrompts)
        if let cachedPrompts, currentData == cachedPromptsData { return cachedPrompts }
        guard let data = currentData,
              let prompts = try? JSONDecoder().decode([CustomPrompt].self, from: data) else {
            if currentData != nil { Logger.infra.error("PreferencesStore: failed to decode customPrompts — resetting") }
            cachedPrompts = []
            cachedPromptsData = nil
            return []
        }
        cachedPrompts = prompts
        cachedPromptsData = data
        return prompts
    }

    func setCustomPrompts(_ prompts: [CustomPrompt]) -> Bool {
        guard let data = try? JSONEncoder().encode(prompts) else {
            Logger.infra.error("PreferencesStore: failed to encode customPrompts — data not saved")
            return false
        }
        cachedPrompts = prompts
        cachedPromptsData = data
        UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.customPrompts)
        return true
    }

    func appRules() -> [AppRule] {
        let currentData = UserDefaults.standard.data(forKey: Constants.UserDefaultsKey.appRules)
        if let cachedAppRules, currentData == cachedAppRulesData { return cachedAppRules }
        guard let data = currentData,
              let rules = try? JSONDecoder().decode([AppRule].self, from: data) else {
            if currentData != nil { Logger.infra.error("PreferencesStore: failed to decode appRules — resetting") }
            cachedAppRules = []
            cachedAppRulesData = nil
            return []
        }
        cachedAppRules = rules
        cachedAppRulesData = data
        return rules
    }

    func setAppRules(_ rules: [AppRule]) -> Bool {
        guard let data = try? JSONEncoder().encode(rules) else {
            Logger.infra.error("PreferencesStore: failed to encode appRules — data not saved")
            return false
        }
        cachedAppRules = rules
        cachedAppRulesData = data
        UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKey.appRules)
        return true
    }

    var isAccessibilityEnabled: Bool {
        if let cachedAccessibility,
           Date().timeIntervalSince(cachedAccessibilityTimestamp) < 3 {
            return cachedAccessibility
        }
        let value = AXIsProcessTrusted()
        cachedAccessibility = value
        cachedAccessibilityTimestamp = Date()
        return value
    }

    func registerAccessibilityObserver() {
        guard accessibilityObserver == nil else { return }
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.invalidateAccessibility() }
        }
    }

    func cleanup() {
        guard let accessibilityObserver else { return }
        DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        self.accessibilityObserver = nil
    }

    static func downloadedModels() -> [String] {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.infra.error("Cannot access Application Support directory")
            return []
        }
        let modelsDir = dir.appendingPathComponent("RefineClone/Models")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path(percentEncoded: false)) else {
            return []
        }
        return contents.filter { $0.hasSuffix(".gguf") }
    }

    private func invalidateAccessibility() {
        cachedAccessibility = nil
    }
}
