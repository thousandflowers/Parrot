import Foundation

enum ModelCatalog {
    static let all: [ModelRecommendation] = {
        buildModels()
    }()

    private static func buildModels() -> [ModelRecommendation] {
        func model(
            id: String, name: String, reason: String, sizeLabel: String,
            ramRequired: Int, urlString: String, isOnboardingCandidate: Bool = false
        ) -> ModelRecommendation? {
            guard let url = URL(string: urlString) else {
                assertionFailure("Invalid model catalog URL: \(urlString)")
                return nil
            }
            return ModelRecommendation(
                id: id, name: name, reason: reason, sizeLabel: sizeLabel,
                ramRequired: ramRequired, url: url, expectedSHA256: nil,
                isOnboardingCandidate: isOnboardingCandidate
            )
        }

        return ([
            model(id: "qwen2.5-0.5b-instruct-q4_k_m", name: "Qwen 2.5 0.5B",
                  reason: String(localized: "model.qwen05b.reason"), sizeLabel: "~400 MB",
                  ramRequired: 1, urlString: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"),
            model(id: "qwen2.5-1.5b-instruct-q4_k_m", name: "Qwen 2.5 1.5B",
                  reason: String(localized: "model.qwen.reason"), sizeLabel: "~1.3 GB",
                  ramRequired: 2, urlString: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
                  isOnboardingCandidate: true),
            model(id: "Llama-3.2-1B-Instruct-Q4_K_M", name: "Llama 3.2 1B",
                  reason: String(localized: "model.llama1b.reason"), sizeLabel: "~1.3 GB",
                  ramRequired: 2, urlString: "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"),
            model(id: "gemma-2-2b-it-Q4_K_M", name: "Gemma 2 2B IT",
                  reason: String(localized: "model.gemma2b.reason"), sizeLabel: "~1.6 GB",
                  ramRequired: 3, urlString: "https://huggingface.co/lmstudio-community/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf"),
            model(id: "Llama-3.2-3B-Instruct-Q4_K_M", name: "Llama 3.2 3B",
                  reason: String(localized: "model.llama3b.reason"), sizeLabel: "~2.0 GB",
                  ramRequired: 3, urlString: "https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"),
            model(id: "Phi-3.5-mini-instruct-Q4_K_M", name: "Phi-3.5 Mini",
                  reason: String(localized: "model.phi.reason"), sizeLabel: "~2.4 GB",
                  ramRequired: 4, urlString: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"),
            model(id: "gemma-4-E2B-it-q4_k_m", name: "Gemma 4 E2B IT (5B)",
                  reason: String(localized: "model.gemma2b.reason"), sizeLabel: "~2.5 GB",
                  ramRequired: 4, urlString: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf",
                  isOnboardingCandidate: true),
            model(id: "gemma-4-E4B-it-q4_k_m", name: "Gemma 4 E4B IT (8B)",
                  reason: String(localized: "model.gemma4b.reason"), sizeLabel: "~4 GB",
                  ramRequired: 6, urlString: "https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf",
                  isOnboardingCandidate: true),
        ] as [ModelRecommendation?]).compactMap { $0 }
    }

    static var onboardingCandidates: [ModelRecommendation] {
        all.filter { $0.isOnboardingCandidate }
    }

    static func recommended(ramGB: Int, language: String) -> ModelRecommendation {
        let fallback: ModelRecommendation = {
            let urlString = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
            guard let url = URL(string: urlString) else {
                assertionFailure("Invalid model URL: \(urlString)")
                return all.first(where: { _ in true }) ?? ModelRecommendation(
                    id: "fallback", name: "Fallback",
                    reason: "", sizeLabel: "0 GB", ramRequired: 0,
                    url: URL(string: "about:blank")!, expectedSHA256: nil, isOnboardingCandidate: false
                )
            }
            return ModelRecommendation(
                id: "qwen2.5-1.5b-instruct-q4_k_m", name: "Qwen 2.5 1.5B",
                reason: "", sizeLabel: "~1.3 GB", ramRequired: 2,
                url: url, expectedSHA256: nil, isOnboardingCandidate: true
            )
        }()
        let chineseLanguages = ["zh", "zh-Hans", "zh-Hant", "zh-HK"]
        if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.lightweightMode)
            || chineseLanguages.contains(language) {
            return all.first { $0.id == "qwen2.5-1.5b-instruct-q4_k_m" } ?? fallback
        }
        return ramGB >= 16
            ? (all.first { $0.id == "gemma-4-E4B-it-q4_k_m" } ?? fallback)
            : (all.first { $0.id == "gemma-4-E2B-it-q4_k_m" } ?? fallback)
    }
}
