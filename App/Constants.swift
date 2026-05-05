import Cocoa

enum Constants {
    static let bundleID = "com.thousandflowers.refineclone"
    // unused: ports managed dynamically via bind(0) in ServerManager
    static let defaultPort = 11434
    static let maxPort = 11444
    static let healthInterval: TimeInterval = 5.0
    static let requestTimeout: TimeInterval = 60.0
    static let cacheTTL: TimeInterval = 3600
    static let cacheMaxEntries = 100
    static let maxRetries = 3
    static let huggingFaceMirror = "https://hf-mirror.com"
    static let huggingFaceMain = "https://huggingface.co"

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
    }
}
