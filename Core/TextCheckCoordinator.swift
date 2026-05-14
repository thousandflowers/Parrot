import Foundation

actor TextCheckCoordinator {
    static let shared = TextCheckCoordinator()
    
    private var currentTask: Task<Void, Never>?
    
    func checkSelectedText() {
        check(type: .grammar, show: { SuggestionPanelController.shared.show(result: $0) })
    }
    
    func checkSelectedText(fromPID pid: pid_t) {
        check(type: .grammar, pid: pid, show: { SuggestionPanelController.shared.show(result: $0) })
    }
    
    func checkFluency() {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        check(type: .fluency, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }
    
    func checkFluency(fromPID pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKey.isFluencyCheckingEnabled) else { return }
        check(type: .fluency, pid: pid, overrideService: true, show: { SuggestionPanelController.shared.showFluency(result: $0) })
    }
    
    private func check(
        type: PromptType,
        pid: pid_t? = nil,
        overrideService: Bool = false,
        show: @escaping @MainActor (CorrectionResult) -> Void
    ) {
        currentTask?.cancel()
        currentTask = Task {
            await performCheck(frontAppPID: pid) { text, resolved, _, _ in
                let serviceType: ServiceType?
                if overrideService {
                    serviceType = resolved.serviceType ?? LLMServiceFactory.resolveFluencyServiceType()
                } else {
                    serviceType = resolved.serviceType
                }
                return try await RequestQueue.shared.enqueue(
                    text: text, type: type, priority: .manual,
                    overrideServiceType: serviceType, overrideCustomPrompt: resolved.prompt
                )
            } onSuccess: { result in
                show(result)
            }
        }
    }
    
    func openFloatingEditor() {
        Task { @MainActor in
            FloatingEditorController.shared.show()
        }
    }
    
    private func performCheck(
        frontAppPID: pid_t? = nil,
        action: @escaping @Sendable (String, (serviceType: ServiceType?, prompt: CustomPrompt?), CFRange?, DetectedTone?) async throws -> CorrectionResult,
        onSuccess: @escaping @MainActor (CorrectionResult) -> Void
    ) async {
        do {
            try Task.checkCancellation()
            
            // 1. Text Extraction (via Service)
            let extracted = try await TextExtractionService.shared.extract(fromPID: frontAppPID)
            
            try Task.checkCancellation()
            
            // 2. Exclusion check
            if let id = extracted.bundleID {
                let excluded = await MainActor.run { PreferencesStore.shared.isExcluded(bundleID: id) }
                if excluded { return }
            }
            
            // 3. Context & Rules
            let language = await MainActor.run { PreferencesStore.shared.language }
            let detectedTone = await ToneDetector.shared.detect(text: extracted.text, language: language)
            
            let resolved = await MainActor.run {
                let prefs = PreferencesStore.shared
                return RuleResolver.resolve(
                    appBundleID: extracted.bundleID,
                    customPrompts: prefs.customPrompts,
                    appRules: prefs.appRules
                )
            }
            
            try Task.checkCancellation()
            
            // 4. Execution
            let rawResult = try await action(extracted.text, resolved, extracted.replacementRange, detectedTone)
            
            // 5. Result Assembly
            let finalResult = CorrectionResult(
                original: rawResult.originalText,
                corrected: rawResult.correctedText,
                modelID: rawResult.modelID,
                explanation: rawResult.explanation,
                confidence: rawResult.confidence,
                customInstruction: rawResult.customInstruction,
                promptType: rawResult.promptType,
                replacementRange: extracted.replacementRange,
                detectedTone: detectedTone.rawValue
            )
            
            try Task.checkCancellation()
            await MainActor.run { onSuccess(finalResult) }
            
        } catch is CancellationError {
            // Silently ignore cancellation
        } catch let error as CorrectionError {
            guard !Task.isCancelled else { return }
            await MainActor.run { SuggestionPanelController.shared.showError(error) }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { SuggestionPanelController.shared.showError(.outputParsingFailed(raw: error.localizedDescription)) }
        }
    }
}
