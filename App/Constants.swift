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

    // MARK: - Local small-model sampling
    // Tighter sampling keeps tiny models (≤3B) from wandering into low-probability
    // hallucinations and repetition loops. repeat_penalty curbs the runaway repetition
    // small GGUF models fall into; top_k/top_p/min_p prune the unreliable tail.
    static let localGrammarSampling = SamplingParams(
        topP: 0.9, topK: 40, minP: 0.05, repeatPenalty: 1.1, seed: nil)
    static let localFluencySampling = SamplingParams(
        topP: 0.95, topK: 60, minP: 0.03, repeatPenalty: 1.1, seed: nil)

    // MARK: - Inline completion (SP1)
    static let completionTemperature: Double = 0.3
    static let completionDefaultMaxWords = 2        // a couple words → granular control + fast
    static let completionDefaultDebounceMs = 350    // wait for a real pause → far fewer inferences
    static let completionMinPrefixChars = 3         // don't suggest on near-empty fields
    // Preceding text sent to the model. Longer = more relevant ("not pulled from a hat"); KV-cache
    // reuse makes the extra context cheap after the first decode.
    static let completionMaxPrefixChars = 800
    static let completionScreenContextMaxChars = 600   // OCR'd on-screen text injected as context
    static let completionScreenContextTTL: TimeInterval = 3   // re-OCR at most this often (anti-stutter)

    /// Self-consistency passes for local grammar checks. Small models are noisy: running
    /// the deterministic grammar task a few times and taking the agreed / most conservative
    /// result removes most one-off wrong or over-aggressive corrections. 1 = disabled.
    /// Only applied to the local service (offline) and only for grammar-type checks.
    static let localSelfConsistencyPasses = 3
    static let defaultConfidence: Double = 0.9
    static let explainMaxTokens = 512
    static let defaultMaxTokens = 1024
    static let defaultContextSize = 4096
    static let serverHealthAttempts = 20
    static let candidateServerPorts = [8080, 11435]
    static let serverStopTimeout: TimeInterval = 5
    static let queueTimeout: TimeInterval = 60
    static let downloadTimeout: TimeInterval = 3600
    static let downloadProgressMinInterval: TimeInterval = 0.1
    static let sha256ChunkSize = 1_048_576
    static let minModelFileSize = 10_000_000
    static let cacheMaxMemoryBytes = 10 * 1024 * 1024
    /// Maximum text length accepted for correction.
    /// Chosen to balance token budget (~2K tokens for 1.5B models) with UX usefulness.
    /// Texts longer than this are rejected with a user-facing error.
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
        static let shortcutDeSlop = "shortcutDeSlop"
        static let shortcutAIPrompt = "shortcutAIPrompt"
        static let presets = "presets"
        static let flows = "flows"
        static let translationLanguage = "translationLanguage"
        static let inlineAnnotationsHoverOnly = "inlineAnnotationsHoverOnly"
        static let aiPromptAutoDetect = "aiPromptAutoDetect"
        static let treeTraversalDisabledBundleIDs = "treeTraversalDisabledBundleIDs"
        static let fallbackLocalModelID = "fallbackLocalModelID"
        static let fallbackOpenAIModel = "fallbackOpenAIModel"
        static let fallbackOllamaModel = "fallbackOllamaModel"
        static let fallbackOpenRouterModel = "fallbackOpenRouterModel"
        // SP1 — inline completion
        static let inlineCompletionEnabled = "inlineCompletionEnabled"
        static let maxCompletionLength = "maxCompletionLength"
        static let completionDebounceMs = "completionDebounceMs"
        static let completionUserPrompt = "completionUserPrompt"
        static let completionModelID = "completionModelID"   // "" = same as main correction model
        static let completionUseAppContext = "completionUseAppContext"
        static let completionUseScreenContext = "completionUseScreenContext"
        static let completionUseClipboardContext = "completionUseClipboardContext"
    }
}
