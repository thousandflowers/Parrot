import Cocoa

enum Constants {
    static let bundleID = "com.thousandflowers.parrot"
    static let healthInterval: TimeInterval = 5.0
    static let requestTimeout: TimeInterval = 60.0
    static let cacheTTL: TimeInterval = 3600
    static let cacheMaxEntries = 100
    static let requestMaxAttempts = 3
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
    static let downloadTimeout: TimeInterval = 3600
    static let downloadProgressMinInterval: TimeInterval = 0.1
    static let sha256ChunkSize = 1_048_576
    static let minModelFileSize = 10_000_000
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
        static let autoCheckEnabled = "autoCheckEnabled"
        static let openAIBaseURL = "openAIBaseURL"
        static let openAIModel = "openAIModel"
        static let isFluencyCheckingEnabled = "isFluencyCheckingEnabled"
        static let fluencyServiceType = "fluencyServiceType"
        static let appRules = "appRules"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaModel = "ollamaModel"
        static let openRouterModel = "openRouterModel"
        static let realtimeEnabled = "realtimeEnabled"
        static let hfToken = "hfToken"
        static let externalModelPaths = "externalModelPaths"
        static let lightweightMode = "lightweightMode"
        static let shortcutGrammar = "shortcutGrammar"
        static let shortcutFluency = "shortcutFluency"
        static let shortcutEditor = "shortcutEditor"
        static let shortcutReplace = "shortcutReplace"
        static let shortcutTranslate = "shortcutTranslate"
        static let shortcutApplyDirect = "shortcutApplyDirect"
        static let shortcutCoach = "shortcutCoach"
        static let shortcutApplyAll = "shortcutApplyAll"
        static let shortcutGrammarFluency = "shortcutGrammarFluency"
        static let presets = "presets"
        static let translationLanguage = "translationLanguage"
    }
}
