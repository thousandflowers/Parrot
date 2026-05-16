import Cocoa

enum Constants {
    static let bundleID = "com.thousandflowers.refineclone"
    static let realtimePollInterval: TimeInterval = 2.0
    static let debounceInterval: TimeInterval = 0.5
    static let requestTimeout: TimeInterval = 60.0
    static let cacheTTL: TimeInterval = 3600
    static let cacheMaxEntries = 100
    static let maxRetries = 3
    static let huggingFaceHost = "huggingface.co"
    static let huggingFaceMirrorHost = "hf-mirror.com"
    static let grammarTemperature: Double = 0.1
    static let fluencyTemperature: Double = 0.3
    static let defaultConfidence: Double = 0.9
    static let explainMaxTokens = 512
    static let defaultMaxTokens = 1024
    static let defaultContextSize = 4096
    static let serverHealthAttempts = 20
    static let queueTimeout: TimeInterval = 60
    static let cacheMaxMemoryBytes = 10 * 1024 * 1024
    static let maxTextLength = 8000

    static let securityExcludedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword4",
        "com.apple.keychainaccess",
        "com.apple.Terminal",
    ]

    enum UserDefaultsKey {
        static let selectedModelID = "selectedModelID"
        static let language = "language"
        static let style = "style"
        static let serviceType = "serviceType"
        static let customPrompts = "customPrompts"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
        static let fluencyServiceType = "fluencyServiceType"
        static let appRules = "appRules"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaModel = "ollamaModel"
        static let openRouterModel = "openRouterModel"
        static let realtimeEnabled = "realtimeEnabled"
        static let shortcutGrammar = "shortcutGrammar"
        static let shortcutFluency = "shortcutFluency"
        static let shortcutEditor  = "shortcutEditor"
        static let shortcutReplace = "shortcutReplace"
        static let shortcutTranslate = "shortcutTranslate"
        static let shortcutApplyDirect = "shortcutApplyDirect"
        static let shortcutCoach = "shortcutCoach"
        static let translationLanguage = "translationLanguage"
        static let lightweightMode = "lightweightMode"
        static let grammarServiceType = "grammarServiceType"
        static let explainServiceType = "explainServiceType"
        static let userDictionaryWords = "userDictionaryWords"
        static let contextWindowSize = "contextWindowSize"
    }
}
