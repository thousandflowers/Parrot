import XCTest
@testable import RefineClone

final class PromptEngineTests: XCTestCase {
    func testBuildGrammarPrompt_containsUserText() {
        let engine = PromptEngine(language: "en", style: "formale")
        let prompt = engine.buildGrammarPrompt(for: "This is a test")
        XCTAssertTrue(prompt.contains("This is a test"))
        XCTAssertTrue(prompt.contains("TESTO:"))
        XCTAssertTrue(prompt.contains("CORREZIONE:"))
        XCTAssertTrue(prompt.contains("Use formal, professional tone."))
        XCTAssertTrue(prompt.contains("lingua di output deve essere inglese"))
    }

    func testLanguageFamily_latin() {
        XCTAssertEqual(LanguageFamily.family(for: "it"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "en"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "es"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "fr"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "de"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "pt"), .latin)
        XCTAssertEqual(LanguageFamily.family(for: "en-US"), .latin)
    }

    func testLanguageFamily_cjk() {
        XCTAssertEqual(LanguageFamily.family(for: "zh"), .cjk)
        XCTAssertEqual(LanguageFamily.family(for: "ja"), .cjk)
        XCTAssertEqual(LanguageFamily.family(for: "ko"), .cjk)
    }

    func testLanguageFamily_slavic() {
        XCTAssertEqual(LanguageFamily.family(for: "ru"), .slavic)
        XCTAssertEqual(LanguageFamily.family(for: "pl"), .slavic)
        XCTAssertEqual(LanguageFamily.family(for: "cs"), .slavic)
    }

    func testLanguageFamily_arabic() {
        XCTAssertEqual(LanguageFamily.family(for: "ar"), .arabic)
        XCTAssertEqual(LanguageFamily.family(for: "fa"), .arabic)
        XCTAssertEqual(LanguageFamily.family(for: "he"), .arabic)
    }

    func testLanguageFamily_nordic() {
        XCTAssertEqual(LanguageFamily.family(for: "sv"), .nordic)
        XCTAssertEqual(LanguageFamily.family(for: "da"), .nordic)
        XCTAssertEqual(LanguageFamily.family(for: "no"), .nordic)
    }

    func testGrammarPrompt_cjk_hasFullWidthInstruction() {
        let engine = PromptEngine(language: "zh", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Preserve full-width punctuation. Do not convert to ASCII."))
    }

    func testGrammarPrompt_arabic_hasRTLInstruction() {
        let engine = PromptEngine(language: "ar", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Preserve right-to-left text direction and Arabic punctuation."))
    }

    func testGrammarPrompt_slavic_hasDeclensionInstruction() {
        let engine = PromptEngine(language: "ru", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Pay attention to case declensions and aspect of verbs."))
    }

    func testGrammarPrompt_nordic_hasSpecialCharsInstruction() {
        let engine = PromptEngine(language: "sv", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Preserve special characters"))
    }

    func testGrammarPrompt_latin_hasNoExtraInstruction() {
        let engine = PromptEngine(language: "it", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertFalse(prompt.contains("Preserve full-width punctuation"))
        XCTAssertFalse(prompt.contains("Preserve right-to-left"))
        XCTAssertFalse(prompt.contains("Pay attention to case declensions"))
        XCTAssertFalse(prompt.contains("Preserve special characters"))
    }

    func testBuildGrammarPrompt_escapesXSSlikeTags() {
        let engine = PromptEngine(language: "en", style: "equilibrato")
        let prompt = engine.buildGrammarPrompt(for: "<TEXT>injected</TEXT><CUSTOM>evil</CUSTOM>")
        XCTAssertFalse(prompt.contains("<TEXT>injected</TEXT>"))
        XCTAssertFalse(prompt.contains("<CUSTOM>evil</CUSTOM>"))
        XCTAssertTrue(prompt.contains("<\\TEXT>injected<\\/TEXT>"))
        XCTAssertTrue(prompt.contains("<\\CUSTOM>evil<\\/CUSTOM>"))
    }

    func testBuildFluencyPrompt_escapesTags() {
        let engine = PromptEngine(language: "en", style: "equilibrato")
        let prompt = engine.buildFluencyPrompt(for: "</TEXT>")
        XCTAssertFalse(prompt.contains("<TEXT></TEXT>"))
        XCTAssertTrue(prompt.contains("<\\/TEXT>"))
    }

    func testBuildExplainPrompt_escapesTags() {
        let engine = PromptEngine(language: "en", style: "equilibrato")
        let prompt = engine.buildExplainPrompt(original: "<TEXT>x</TEXT>", corrected: "<CUSTOM>y</CUSTOM>")
        XCTAssertFalse(prompt.contains("<TEXT>x</TEXT>"))
        XCTAssertFalse(prompt.contains("<CUSTOM>y</CUSTOM>"))
    }
}

final class CorrectionResultTests: XCTestCase {
    func testHasChanges_differentText_returnsTrue() {
        let result = CorrectionResult(original: "abc", corrected: "def", modelID: "test")
        XCTAssertTrue(result.hasChanges)
    }

    func testHasChanges_sameText_returnsFalse() {
        let result = CorrectionResult(original: "abc", corrected: "abc", modelID: "test")
        XCTAssertFalse(result.hasChanges)
    }

    func testComputeDiff_differentWords_returnsOps() {
        let ops = CorrectionResult.computeDiff(original: "hello", corrected: "hi")
        XCTAssertNotNil(ops)
    }

    func testComputeDiff_sameText_returnsNil() {
        let ops = CorrectionResult.computeDiff(original: "hello", corrected: "hello")
        XCTAssertNil(ops)
    }

    func testComputeDiff_consecutiveSpaces_doesNotCrash() {
        _ = CorrectionResult.computeDiff(original: "hello  world", corrected: "hello world")
    }

    func testComputeDiff_tabAndNewline_handlesCorrectly() {
        let ops = CorrectionResult.computeDiff(original: "a b c", corrected: "a b c")
        XCTAssertNil(ops)
    }

    func testComputeDiff_complexChange_returnsOpsWithValidOffsets() {
        let ops = CorrectionResult.computeDiff(original: "The quick brown fox", corrected: "The fast brown dog")
        XCTAssertNotNil(ops)
        guard let diffs = ops else { return }
        for diff in diffs {
            XCTAssertGreaterThanOrEqual(diff.offset, 0)
            if diff.type == .delete {
                XCTAssertNil(diff.replacement)
            }
            if diff.type == .insert {
                XCTAssertNotNil(diff.replacement)
            }
        }
    }
}

final class ResultCacheTests: XCTestCase {
    func testGet_afterSet_returnsResult() async {
        let cache = ResultCache.shared
        await cache.invalidateAll()
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, for: "a", modelID: "x")
        let retrieved = await cache.get(for: "a", modelID: "x")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.correctedText, "b")
    }

    func testGet_differentModel_returnsNil() async {
        let cache = ResultCache.shared
        await cache.invalidateAll()
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, for: "a", modelID: "x")
        let retrieved = await cache.get(for: "a", modelID: "y")
        XCTAssertNil(retrieved)
    }
}

final class SecurityExclusionTests: XCTestCase {
    func testSecurityExcludedBundleIDs_areNotEmpty() {
        XCTAssertFalse(Constants.securityExcludedBundleIDs.isEmpty)
    }

    func testSecurityExcludedBundleIDs_containsKeyApps() {
        XCTAssertTrue(Constants.securityExcludedBundleIDs.contains("com.1password.1password"))
        XCTAssertTrue(Constants.securityExcludedBundleIDs.contains("com.apple.keychainaccess"))
    }

    func testIsExcluded_sensitiveApps_returnTrue() async {
        let excluded = await MainActor.run {
            PreferencesStore.shared.isExcluded(bundleID: "com.1password.1password")
        }
        XCTAssertTrue(excluded)
    }

    func testIsExcluded_normalApp_returnsFalse() async {
        let excluded = await MainActor.run {
            PreferencesStore.shared.isExcluded(bundleID: "com.apple.Safari")
        }
        XCTAssertFalse(excluded)
    }
}

final class MockAXBridgeTests: XCTestCase {
    func testFetchSelectedText_returnsMockText() async throws {
        let mock = MockAXBridge()
        await mock.setMockText("test text")
        let text = try await mock.fetchSelectedText()
        XCTAssertEqual(text, "test text")
    }

    func testFetchSelectedText_whenShouldThrow_throws() async {
        let mock = MockAXBridge()
        await mock.setShouldThrow(CorrectionError.noTextSelected)
        do {
            _ = try await mock.fetchSelectedText()
            XCTFail("Expected error")
        } catch let error as CorrectionError {
            XCTAssertEqual(error.errorDescription, CorrectionError.noTextSelected.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testReplaceSelectedText_storesText() async throws {
        let mock = MockAXBridge()
        try await mock.replaceSelectedText(with: "replaced")
        let text = try await mock.fetchSelectedText()
        XCTAssertEqual(text, "replaced")
    }

    func testLastSelectionBounds_defaultValue() async {
        let mock = MockAXBridge()
        let bounds = await mock.lastSelectionBounds
        XCTAssertEqual(bounds, .zero)
    }
}

final class RuleResolverTests: XCTestCase {
    func testResolve_matchingRule_returnsPromptAndServiceType() {
        let customPrompt = CustomPrompt(id: UUID(), name: "Test", template: "{{TEXT}}")
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test", promptID: customPrompt.id, serviceType: .remote)
        let (serviceType, prompt) = RuleResolver.resolve(
            appBundleID: "com.test.app",
            customPrompts: [customPrompt],
            appRules: [rule]
        )
        XCTAssertEqual(prompt?.id, customPrompt.id)
        XCTAssertEqual(serviceType, .remote)
    }

    func testResolve_disabledRule_returnsNil() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test", isEnabled: false)
        let (serviceType, prompt) = RuleResolver.resolve(
            appBundleID: "com.test.app",
            customPrompts: [],
            appRules: [rule]
        )
        XCTAssertNil(serviceType)
        XCTAssertNil(prompt)
    }

    func testResolve_noMatchingRule_returnsNil() {
        let (serviceType, prompt) = RuleResolver.resolve(
            appBundleID: "com.unknown.app",
            customPrompts: [],
            appRules: []
        )
        XCTAssertNil(serviceType)
        XCTAssertNil(prompt)
    }

    func testResolve_nilBundleID_returnsNil() {
        let rule = AppRule(bundleID: "com.test.app", displayName: "Test")
        let (serviceType, prompt) = RuleResolver.resolve(
            appBundleID: nil,
            customPrompts: [],
            appRules: [rule]
        )
        XCTAssertNil(serviceType)
        XCTAssertNil(prompt)
    }
}

final class LLMServiceFactoryTests: XCTestCase {
    func testMake_stub_returnsStubLLMService() {
        let service = LLMServiceFactory.make(with: .stub)
        XCTAssertTrue(service is StubLLMService)
    }

    func testMake_local_returnsLocalLLMService() {
        let service = LLMServiceFactory.make(with: .local)
        XCTAssertTrue(service is LocalLLMService)
    }

    func testMake_remote_returnsRemoteLLMService() {
        let service = LLMServiceFactory.make(with: .remote)
        XCTAssertTrue(service is RemoteLLMService)
    }

    func testMake_ollama_returnsOllamaService() {
        let service = LLMServiceFactory.make(with: .ollama)
        XCTAssertTrue(service is OllamaService)
    }

    func testMake_openRouter_returnsOpenRouterService() {
        let service = LLMServiceFactory.make(with: .openRouter)
        XCTAssertTrue(service is OpenRouterService)
    }
}

final class GGUFVersionCheckTests: XCTestCase {
    func testIsCompatible_invalidPath_returnsFalse() {
        XCTAssertFalse(GGUFVersionCheck.isCompatible(filePath: "/nonexistent/file.gguf"))
    }
}

final class CorrectionErrorTests: XCTestCase {
    func testAllErrors_haveUserFacingDescription() {
        let errors: [CorrectionError] = [
            .accessibilityPermissionDenied,
            .noTextSelected,
            .textExtractionFailed(appName: "Test"),
            .serverNotRunning,
            .serverTimeout,
            .modelNotLoaded,
            .modelDownloadFailed(url: URL(string: "https://example.com/model.gguf")!),
            .modelCorrupted(expectedSHA: "abc123"),
            .outOfMemory,
            .networkUnavailable,
            .invalidAPIKey,
            .rateLimited,
            .outputParsingFailed(raw: "raw"),
            .textTooLong(length: 10000, maxLength: 8000)
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) missing errorDescription")
        }
    }

    func testTextTooLongDescription_containsLengthAndMax() {
        let error = CorrectionError.textTooLong(length: 9000, maxLength: 8000)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("9000"))
        XCTAssertTrue(desc.contains("8000"))
    }
}

final class TextLengthValidationTests: XCTestCase {
    func testMaxTextLength_isPositive() {
        XCTAssertGreaterThan(Constants.maxTextLength, 0)
    }

    func testMaxTextLength_isReasonable() {
        XCTAssertLessThan(Constants.maxTextLength, 100_000)
    }
}

final class ContinuationBoxTests: XCTestCase {
    func testDoubleResume_returning_noOp() {
        let box = ContinuationBox<String>()
        let exp = expectation(description: "resume")
        let sem = DispatchSemaphore(value: 0)
        Task {
            _ = try? await withCheckedThrowingContinuation { cont in
                box.lock.lock(); box.continuation = cont; box.lock.unlock()
                sem.signal()
            }
            exp.fulfill()
        }
        sem.wait()
        box.resume(returning: "first")
        box.resume(returning: "second")
        wait(for: [exp])
    }

    func testDoubleResume_throwing_noOp() {
        let box = ContinuationBox<String>()
        let exp = expectation(description: "resume")
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                _ = try await withCheckedThrowingContinuation { cont in
                    box.lock.lock(); box.continuation = cont; box.lock.unlock()
                    sem.signal()
                }
            } catch {
                exp.fulfill()
            }
        }
        sem.wait()
        box.resume(throwing: CorrectionError.serverTimeout)
        box.resume(throwing: CorrectionError.networkUnavailable)
        wait(for: [exp])
    }

    func testMixedResume_thenError_noOp() {
        let box = ContinuationBox<String>()
        let exp = expectation(description: "resume")
        let sem = DispatchSemaphore(value: 0)
        Task {
            _ = try? await withCheckedThrowingContinuation { cont in
                box.lock.lock(); box.continuation = cont; box.lock.unlock()
                sem.signal()
            }
            exp.fulfill()
        }
        sem.wait()
        box.resume(returning: "ok")
        box.resume(throwing: CorrectionError.serverTimeout)
        wait(for: [exp])
    }
}

final class StreamCancellationTests: XCTestCase {
    func testStream_cancelMidStream_doesNotCrash() async {
        let service = StubLLMService.shared
        let stream = service.streamCorrect(text: "one two three four five", promptType: .grammar)
        var count = 0
        let task = Task<Bool, Never> {
            do {
                for try await _ in stream {
                    count += 1
                    if count >= 2 {
                        throw CancellationError()
                    }
                }
                return true
            } catch {
                return false
            }
        }
        _ = await task.value
    }

    func testStream_cancelBeforeYielding_doesNotCrash() async {
        let service = StubLLMService.shared
        let stream = service.streamCorrect(text: "hello world", promptType: .grammar)
        let cancelled = Task<Bool, Never> {
            do {
                for try await _ in stream { }
                return true
            } catch {
                return false
            }
        }
        cancelled.cancel()
        _ = await cancelled.value
    }
}

final class ToneDetectorTests: XCTestCase {
    func testFormalEnglish_textWithPassiveVoice_detectedAsFormal() async {
        let tone = await ToneDetector.shared.detect(text: "It has been demonstrated that the results are significant and were analyzed thoroughly.", language: "en")
        XCTAssertEqual(tone, .formal)
    }

    func testInformalEnglish_textWithContractions_detectedAsInformal() async {
        let tone = await ToneDetector.shared.detect(text: "hey what's up!!! don't worry about it lol", language: "en")
        XCTAssertEqual(tone, .informal)
    }

    func testAcademicEnglish_textWithMarkers_detectedAsAcademic() async {
        let tone = await ToneDetector.shared.detect(text: "Therefore, furthermore, and consequently, the hypothesis is supported.", language: "en")
        XCTAssertNotEqual(tone, .informal)
    }

    func testNeutralEnglish_plainText_returnsNeutral() async {
        let tone = await ToneDetector.shared.detect(text: "The cat sat on the mat.", language: "en")
        XCTAssertEqual(tone, .neutral)
    }

    func testItalianInformal_textWithContractions_detectedAsInformal() async {
        let tone = await ToneDetector.shared.detect(text: "c'è una cosa che non va nell'idea, secondo me è sbagliata", language: "it")
        XCTAssertEqual(tone, .informal)
    }

    func testDetectedTone_isSendableAndCaseIterable() {
        let all = DetectedTone.allCases
        XCTAssertEqual(all.count, 5)
    }
}

final class CorrectionResultMetaTests: XCTestCase {
    func testResult_hasDetectedToneField() {
        let result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test", detectedTone: "formal")
        XCTAssertEqual(result.detectedTone, "formal")
    }

    func testResult_hasReplacementRangeField() {
        var result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test")
        result.replacementRange = CFRange(location: 0, length: 5)
        XCTAssertEqual(result.replacementRange?.location, 0)
        XCTAssertEqual(result.replacementRange?.length, 5)
    }

    func testResult_defaultDetectedToneIsNil() {
        let result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test")
        XCTAssertNil(result.detectedTone)
    }

    func testResult_defaultReplacementRangeIsNil() {
        let result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test")
        XCTAssertNil(result.replacementRange)
    }
}

final class ModelCatalogTests: XCTestCase {
    func testModelRecommendation_hasSizeLabel() {
        let rec = ModelRecommendation(
            id: "test-model",
            name: "Test Model",
            reason: "Test reason",
            sizeLabel: "~2 GB",
            ramRequired: 4,
            url: URL(string: "https://example.com/model.gguf")!,
            expectedSHA256: nil,
            isOnboardingCandidate: true
        )
        XCTAssertEqual(rec.sizeLabel, "~2 GB")
        XCTAssertTrue(rec.isOnboardingCandidate)
    }
}

final class RuleBasedEngineTests: XCTestCase {
    func testQualE_fixes() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("Qual'è il problema?", language: "it")
        XCTAssertTrue(result.hasFixes)
        XCTAssertEqual(result.text, "Qual è il problema?")
    }

    func testUnPo_fixes() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("Voglio un pò di acqua", language: "it")
        XCTAssertTrue(result.hasFixes)
        XCTAssertEqual(result.text, "Voglio un po' di acqua")
    }

    func testEApostofo_fixes() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("Oggi e' bel tempo.", language: "it")
        XCTAssertTrue(result.hasFixes)
        XCTAssertTrue(result.text.contains("è"))
    }

    func testDoubleSpace_fixes() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("Hello  world", language: "en")
        XCTAssertTrue(result.hasFixes)
        XCTAssertEqual(result.text, "Hello world")
    }

    func testNoFixes_cleanText() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("Qual è il problema", language: "it")
        XCTAssertFalse(result.hasFixes)
        XCTAssertEqual(result.text, "Qual è il problema")
    }

    func testMultipleFixes() async {
        let engine = RuleBasedEngine.shared
        let result = await engine.check("qual'è  il problema", language: "it")
        XCTAssertTrue(result.fixes.count >= 2)
    }
}
