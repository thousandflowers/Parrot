import Foundation

enum AppCategory: String, Codable, Sendable, CaseIterable {
    case code, email, chat, notes, browser, terminal, social, general

    static func detect(bundleID: String) -> AppCategory {
        if AppDetector.isCode(bundleID) { return .code }
        if AppDetector.isTerminal(bundleID) { return .terminal }
        if AppDetector.isBrowser(bundleID) { return .browser }
        if AppDetector.isEmail(bundleID) { return .email }
        if AppDetector.isChat(bundleID) { return .chat }
        if AppDetector.isNotes(bundleID) { return .notes }
        if AppDetector.isSocial(bundleID) { return .social }
        return .general
    }
}

struct AppProfile: Codable, Sendable {
    var completionEnabled: Bool?
    var grammarEnabled: Bool?
    var maxCompletionLength: Int?
    var completionDebounceMs: Int?
    var styleInstructions: String?
    var screenContextEnabled: Bool?

    static let `default` = AppProfile()
}

struct AppRule: Identifiable, Codable, Sendable {
    let id: UUID
    var bundleID: String
    var displayName: String
    var promptID: UUID?
    var serviceType: ServiceType?
    var isEnabled: Bool
    var profile: AppProfile
    var category: AppCategory

    init(
        id: UUID = UUID(),
        bundleID: String,
        displayName: String,
        promptID: UUID? = nil,
        serviceType: ServiceType? = nil,
        isEnabled: Bool = true,
        profile: AppProfile = AppProfile(),
        category: AppCategory? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.promptID = promptID
        self.serviceType = serviceType
        self.isEnabled = isEnabled
        self.profile = profile
        self.category = category ?? AppCategory.detect(bundleID: bundleID)
    }
}

extension PreferencesStore {
    /// Effective per-app config: explicit rule overrides → category defaults → global.
    func effectiveProfile(for bundleID: String) -> AppProfile {
        if let rule = appRules.first(where: { $0.bundleID == bundleID }), rule.isEnabled {
            return rule.profile
        }
        let cat = AppCategory.detect(bundleID: bundleID)
        return categoryDefaultProfile(cat)
    }

    private func categoryDefaultProfile(_ cat: AppCategory) -> AppProfile {
        switch cat {
        case .code:
            return AppProfile(completionEnabled: true, grammarEnabled: false, maxCompletionLength: 4, completionDebounceMs: 80, screenContextEnabled: false)
        case .terminal:
            return AppProfile(completionEnabled: false, grammarEnabled: false, maxCompletionLength: 2, screenContextEnabled: false)
        case .email:
            return AppProfile(completionEnabled: true, grammarEnabled: true, maxCompletionLength: 8, completionDebounceMs: 300, screenContextEnabled: true)
        case .chat:
            return AppProfile(completionEnabled: true, grammarEnabled: nil, maxCompletionLength: 5, completionDebounceMs: 250, styleInstructions: "friendly and concise")
        case .notes:
            return AppProfile(completionEnabled: true, grammarEnabled: true, maxCompletionLength: 8, completionDebounceMs: 200, screenContextEnabled: false)
        case .browser:
            return AppProfile(completionEnabled: true, grammarEnabled: true, maxCompletionLength: 6, completionDebounceMs: 250)
        case .social:
            return AppProfile(completionEnabled: true, grammarEnabled: false, maxCompletionLength: 3, completionDebounceMs: 180, styleInstructions: "casual and direct")
        case .general:
            return AppProfile()
        }
    }
}
