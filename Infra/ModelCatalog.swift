import Foundation

enum ModelCatalog {
    static let all: [ModelRecommendation] = [
        ModelRecommendation(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B",
            reason: "Minimo consumo RAM — ideale per testi brevi e lingua cinese",
            sizeLabel: "~1.3 GB",
            ramRequired: 2,
            url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
        ModelRecommendation(
            id: "gemma-4-E2B-it-q4_k_m",
            name: "Gemma 4 E2B IT (5B)",
            reason: "Buona qualità per lingue occidentali — Mac con meno di 16 GB",
            sizeLabel: "~2.5 GB",
            ramRequired: 4,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
        ModelRecommendation(
            id: "gemma-4-E4B-it-q4_k_m",
            name: "Gemma 4 E4B IT (8B)",
            reason: "Massima qualità per lingue occidentali — richiede Mac con 16 GB RAM o più",
            sizeLabel: "~4 GB",
            ramRequired: 6,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        ),
    ]

    static var onboardingCandidates: [ModelRecommendation] {
        all.filter { $0.isOnboardingCandidate }
    }

    static func recommended(ramGB: Int, language: String) -> ModelRecommendation {
        let chineseLanguages = ["zh", "zh-Hans", "zh-Hant", "zh-HK"]
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.lightweightMode)
            || chineseLanguages.contains(language) {
            return all.first { $0.id == "qwen2.5-1.5b-instruct-q4_k_m" }!
        }
        return ramGB >= 16
            ? all.first { $0.id == "gemma-4-E4B-it-q4_k_m" }!
            : all.first { $0.id == "gemma-4-E2B-it-q4_k_m" }!
    }
}
