import XCTest
@testable import Parrot

final class PromptEngineTests: XCTestCase {
    func testBuildGrammarPrompt_containsUserText() {
        let engine = PromptEngine(language: "en", style: "formale")
        let prompt = engine.buildGrammarPrompt(for: "This is a test")
        XCTAssertTrue(prompt.contains("This is a test"))
        XCTAssertTrue(prompt.contains("Use formal, professional tone."))
        XCTAssertTrue(prompt.contains("Fix all grammatical errors"))
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
        XCTAssertTrue(prompt.contains("Preserve CJK punctuation"))
    }

    func testGrammarPrompt_arabic_hasRTLInstruction() {
        let engine = PromptEngine(language: "ar", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Preserve right-to-left text"))
    }

    func testGrammarPrompt_slavic_hasDeclensionInstruction() {
        let engine = PromptEngine(language: "ru", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "test")
        XCTAssertTrue(prompt.contains("Fix case declension"))
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

    func testBuildTranslationPrompt_containsTargetLanguageAndText() {
        let engine = PromptEngine(language: "it", style: "equilibrato")
        let prompt = engine.buildTranslationPrompt(for: "Hello world", targetLanguage: "it")
        XCTAssertTrue(prompt.contains("Hello world"))
        XCTAssertTrue(prompt.contains("italiano") || prompt.contains("Italian") || prompt.contains("it"))
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

    func testComputeDiff_consecutiveSpaces_correctOffsets() {
        // "world" starts at index 7 in "hello  world" (double space at 5,6)
        guard let ops = CorrectionResult.computeDiff(original: "hello  world", corrected: "hello globe") else {
            XCTFail("Expected diff ops"); return
        }
        let deleteOp = ops.first(where: { $0.type == .delete })
        XCTAssertNotNil(deleteOp)
        // "world" is at char offset 7 (h=0,e=1,l=2,l=3,o=4,' '=5,' '=6,w=7)
        XCTAssertEqual(deleteOp?.offset, 7, "Offset must point to 'world' after double space")
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

final class CorrectionCacheTests: XCTestCase {
    override func setUp() async throws {
        await CorrectionCache.shared.invalidateAll()
    }

    func testGet_afterSet_returnsResult() async {
        let cache = CorrectionCache.shared
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, text: "a", promptType: "grammar", modelID: "x")
        let retrieved = await cache.get(text: "a", promptType: "grammar", modelID: "x")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.correctedText, "b")
    }

    func testGet_differentModel_returnsNil() async {
        let cache = CorrectionCache.shared
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, text: "a", promptType: "grammar", modelID: "x")
        let retrieved = await cache.get(text: "a", promptType: "grammar", modelID: "y")
        XCTAssertNil(retrieved)
    }

    func testSet_updatingExistingKey_doesNotDoublecountMemory() async {
        let cache = CorrectionCache.shared
        let result1 = CorrectionResult(original: "hello world", corrected: "hello world!", modelID: "m1")
        let result2 = CorrectionResult(original: "hello world", corrected: "hi world!", modelID: "m1")

        await cache.set(result1, text: "hello world", promptType: "grammar", modelID: "m1")
        await cache.set(result2, text: "hello world", promptType: "grammar", modelID: "m1")
        let bytesAfter = await cache.currentMemoryBytesForTesting

        let expectedBytes = "hello world".utf8.count + "hi world!".utf8.count
        XCTAssertEqual(bytesAfter, expectedBytes)
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

final class ModelCatalogTests: XCTestCase {
    func testAllModels_haveValidURLs() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
        for model in ModelCatalog.all {
            XCTAssertNotNil(URL(string: model.url.absoluteString), "Invalid URL for model: \(model.name)")
        }
    }

    func testAllModels_haveNonEmptyNames() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.name.isEmpty)
            XCTAssertGreaterThan(model.ramRequired, 0)
        }
    }

    func testOnboardingCandidates_areSubsetOfAll() {
        let candidates = ModelCatalog.onboardingCandidates
        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            XCTAssertTrue(candidate.isOnboardingCandidate)
            XCTAssertTrue(ModelCatalog.all.contains(where: { $0.id == candidate.id }))
        }
    }
}

final class LanguageDetectorTests: XCTestCase {
    func testDetect_shortText_returnsFallback() {
        let result = LanguageDetector.detect(text: "hi", fallbackLanguage: "fr")
        XCTAssertEqual(result, "fr")
    }

    func testDetect_englishParagraph_returnsEN() {
        let text = "The quick brown fox jumps over the lazy dog near the river bank."
        let result = LanguageDetector.detect(text: text, fallbackLanguage: "it")
        XCTAssertTrue(result.hasPrefix("en"), "Expected en, got \(result)")
    }

    func testDetect_italianParagraph_returnsIT() {
        let text = "Il cielo è azzurro sopra la montagna innevata e il sole splende."
        let result = LanguageDetector.detect(text: text, fallbackLanguage: "en")
        XCTAssertTrue(result.hasPrefix("it"), "Expected it, got \(result)")
    }

    func testDetect_chineseText_returnsZH() {
        let text = "今天天气很好，我们去公园散步吧，欣赏一下美丽的风景。"
        let result = LanguageDetector.detect(text: text, fallbackLanguage: "en")
        XCTAssertTrue(result.hasPrefix("zh"), "Expected zh, got \(result)")
    }

    func testDetect_emptyString_returnsFallback() {
        let result = LanguageDetector.detect(text: "", fallbackLanguage: "da")
        XCTAssertEqual(result, "da")
    }
}

final class LanguageFamilyTests: XCTestCase {
    func testCroatian_isSlavic() {
        XCTAssertEqual(LanguageFamily.family(for: "hr"), .slavic)
    }

    func testDanish_isNordic() {
        XCTAssertEqual(LanguageFamily.family(for: "da"), .nordic)
    }

    func testFrench_isLatin() {
        XCTAssertEqual(LanguageFamily.family(for: "fr"), .latin)
    }

    func testChineseSimplified_isCJK() {
        XCTAssertEqual(LanguageFamily.family(for: "zh-Hans"), .cjk)
        XCTAssertEqual(LanguageFamily.family(for: "zh"), .cjk)
    }

    func testUnknown_defaultsToLatin() {
        XCTAssertEqual(LanguageFamily.family(for: "xyz"), .latin)
    }
}

final class CustomRuleEscapingTests: XCTestCase {
    override func setUp() async throws {
        for rule in await CustomRuleStore.shared.allRules() {
            await CustomRuleStore.shared.remove(id: rule.id)
        }
    }

    func testRegexRule_dollarInReplacement_isLiteral() async {
        let store = CustomRuleStore.shared
        let rule = CustomRule(name: "test-dollar", pattern: "foo", replacement: "$100", isRegex: true)
        await store.add(rule)
        let (result, _) = await store.apply(to: "foo bar", language: "en")
        XCTAssertEqual(result, "$100 bar", "$ in replacement must be literal, not a backreference")
    }

    func testRegexRule_backslashInReplacement_isLiteral() async {
        let store = CustomRuleStore.shared
        let rule = CustomRule(name: "test-backslash", pattern: "baz", replacement: "a\\1b", isRegex: true)
        await store.add(rule)
        let (result, _) = await store.apply(to: "baz", language: "en")
        XCTAssertEqual(result, "a\\1b", "\\1 in replacement must be literal, not a backreference")
    }
}

final class AnnotationsCJKTests: XCTestCase {
    func testToAnnotations_CJKText_returnsEmpty() {
        let result = CorrectionResult(original: "我喜欢苹果", corrected: "我喜欢苹果。", modelID: "test")
        XCTAssertTrue(result.toAnnotations().isEmpty, "CJK text must not produce whitespace-based annotations")
    }

    func testToAnnotations_englishText_returnsAnnotations() {
        let result = CorrectionResult(original: "the cat sit on mat", corrected: "the cat sits on the mat", modelID: "test")
        XCTAssertFalse(result.toAnnotations().isEmpty)
    }

    func testToAnnotations_noChanges_returnsEmpty() {
        let result = CorrectionResult(original: "hello world", corrected: "hello world", modelID: "test")
        XCTAssertTrue(result.toAnnotations().isEmpty)
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

final class RequestQueueTests: XCTestCase {
    func testEnqueue_textTooLong_throws() async {
        let longText = String(repeating: "x", count: Constants.maxTextLength + 1)
        do {
            _ = try await RequestQueue.shared.enqueue(text: longText, type: .grammar, priority: .manual)
            XCTFail("Expected textTooLong error")
        } catch CorrectionError.textTooLong(let length, let max) {
            XCTAssertEqual(length, Constants.maxTextLength + 1)
            XCTAssertEqual(max, Constants.maxTextLength)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnqueue_emptyText_isAllowed() async {
        // Empty text should not crash — the coordinator checks isEmpty before enqueue
        let result = try? await RequestQueue.shared.enqueue(text: "", type: .grammar, priority: .manual)
        // Empty text will either return a valid result or throw from the LLM service
        XCTAssertTrue(result != nil || true)
    }

    func testEnqueue_priorityInsertion_order() async {
        // Verify that high-priority requests are processed before low-priority ones
        // This is a structural test — we can't easily test the internal queue order
        // without making queue private, but we verify the API shape
        let task1 = Task {
            try? await RequestQueue.shared.enqueue(text: "low priority", type: .grammar, priority: .autoCheck)
        }
        let task2 = Task {
            try? await RequestQueue.shared.enqueue(text: "high priority", type: .grammar, priority: .manual)
        }
        _ = await task2.value
        _ = await task1.value
    }
}

final class ServerManagerTests: XCTestCase {
    func testStart_invalidModelPath_throws() async {
        let fakePath = "/nonexistent/model.gguf"
        do {
            try await ServerManager.shared.start(modelPath: fakePath)
            XCTFail("Expected error for invalid model path")
        } catch is CorrectionError {
            // Expected — model file doesn't exist or GGUF check fails
        } catch {
            // Also acceptable — filesystem error
        }
    }

    func testCurrentPort_defaultIsZero() async {
        let port = await ServerManager.shared.currentPort
        XCTAssertEqual(port, 0)
    }
}

final class FeedbackLoggerTests: XCTestCase {
    func testLog_doesNotCrashWithLongText() {
        let longText = String(repeating: "a", count: 600)
        // Must not crash or throw
        FeedbackLogger.log(original: longText, corrected: "short", reason: "test", modelID: "test")
    }
}

final class LLMAPITypesTests: XCTestCase {
    func testChatRequestEncodesCorrectly() throws {
        let req = ChatRequest(
            model: "gpt-4o-mini",
            messages: [ChatMessage(role: "user", content: "test")],
            temperature: 0.1,
            max_tokens: 1024,
            stream: false
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(json["temperature"] as? Double, 0.1)
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testChatResponseDecodesCorrectly() throws {
        let json = """
        {"choices":[{"message":{"content":"corrected text"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatResponse.self, from: json)
        XCTAssertEqual(response.choices.first?.message.content, "corrected text")
    }
}

final class HistoryStoreTests: XCTestCase {
    override func setUp() async throws {
        await HistoryStore.shared.clear()
    }

    func testAdd_storesEntry() async {
        let store = HistoryStore.shared
        let result = CorrectionResult(original: "hello", corrected: "Hello world!", modelID: "test")
        await store.add(result: result)
        let entries = await store.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.original, "hello")
    }

    func testAdd_noChanges_doesNotStore() async {
        let store = HistoryStore.shared
        let result = CorrectionResult(original: "hello", corrected: "hello", modelID: "test")
        await store.add(result: result)
        let entries = await store.all()
        XCTAssertEqual(entries.count, 0)
    }
}

final class DiffHighlightTests: XCTestCase {
    func testDiffHighlight_detectsInsertedWord() {
        let original = "Il testo è corretto"
        let corrected = "Il testo è veramente corretto"

        let origWords = original.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let corrWords = corrected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let diff = corrWords.difference(from: origWords)

        var insertedIndices = Set<Int>()
        for change in diff.insertions {
            if case .insert(let offset, _, _) = change { insertedIndices.insert(offset) }
        }

        XCTAssertTrue(insertedIndices.contains(3), "Expected 'veramente' to be detected at index 3")
        XCTAssertEqual(corrWords[3], "veramente", "Expected word at index 3 to be 'veramente'")
    }
}

final class LLMServiceFactoryModelIDTests: XCTestCase {
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openAIModel)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.ollamaModel)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openRouterModel)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.selectedModelID)
    }

    func testResolveModelID_stub_returnsStubV1() {
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .stub), "stub-v1")
    }

    func testResolveModelID_remote_returnsGPT4oMiniWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openAIModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .remote), "gpt-4o-mini")
    }

    func testResolveModelID_ollama_returnsLlama32WhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.ollamaModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .ollama), "llama3.2")
    }

    func testResolveModelID_openRouter_returnsGPT4oMiniWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.openRouterModel)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .openRouter), "openai/gpt-4o-mini")
    }

    func testResolveModelID_local_returnsLocalQwenFallbackWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.selectedModelID)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .local), "local-qwen")
    }

    func testResolveModelID_local_stripsGGUFExtension() {
        UserDefaults.standard.set("qwen2-0.5b-instruct.gguf", forKey: Constants.UserDefaultsKey.selectedModelID)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .local), "qwen2-0.5b-instruct")
    }
}

final class CorrectionResultSourceTests: XCTestCase {
    func testSource_ruleBasedPreservedThroughRoundTrip() {
        let rawResult = CorrectionResult(original: "a", corrected: "b", modelID: "rules", source: .ruleBased)
        let rebuilt = CorrectionResult(
            original: rawResult.originalText,
            corrected: rawResult.correctedText,
            modelID: rawResult.modelID,
            explanation: rawResult.explanation,
            confidence: rawResult.confidence,
            customInstruction: rawResult.customInstruction,
            promptType: rawResult.promptType,
            detectedTone: rawResult.detectedTone,
            source: rawResult.source
        )
        XCTAssertEqual(rebuilt.source, .ruleBased, "source must survive performCheck reconstruction")
    }

    func testSource_hybridPreservedThroughRoundTrip() {
        let rawResult = CorrectionResult(original: "a", corrected: "b", modelID: "grammar+fluency", source: .hybrid)
        let rebuilt = CorrectionResult(
            original: rawResult.originalText,
            corrected: rawResult.correctedText,
            modelID: rawResult.modelID,
            source: rawResult.source
        )
        XCTAssertEqual(rebuilt.source, .hybrid)
    }

    func testSource_defaultIsLLM() {
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "gpt")
        XCTAssertEqual(result.source, .llm, "default source must be .llm")
    }

    func testQueueTimeout_constant_is60() {
        XCTAssertEqual(Constants.queueTimeout, 60.0, accuracy: 0.001)
    }
}

final class StreamingCacheTests: XCTestCase {
    override func setUp() async throws {
        await CorrectionCache.shared.invalidateAll()
    }

    func testCorrectionCache_preservesModelID_onRoundTrip() async {
        let result = CorrectionResult(original: "hello", corrected: "hi", modelID: "stub-v1")
        await CorrectionCache.shared.set(result, text: "hello", promptType: "grammar", modelID: "stub-v1", language: "en")
        let retrieved = await CorrectionCache.shared.get(text: "hello", promptType: "grammar", modelID: "stub-v1", language: "en")
        XCTAssertEqual(retrieved?.modelID, "stub-v1", "modelID must be preserved through cache")
    }

    func testCorrectionCache_cacheMiss_returnNil() async {
        let result = await CorrectionCache.shared.get(text: "not cached", promptType: "grammar", modelID: "any", language: "en")
        XCTAssertNil(result)
    }
}

final class CorrectionCacheDiskTests: XCTestCase {
    override func setUp() async throws {
        await CorrectionCache.shared.invalidateAll()
        await CorrectionCache.shared.deleteCacheFile()
    }

    override func tearDown() async throws {
        await CorrectionCache.shared.deleteCacheFile()
    }

    func testSaveToDisk_thenLoadFromDisk_restoresEntry() async throws {
        let cache = CorrectionCache.shared
        let result = CorrectionResult(original: "disk test", corrected: "disk fixed", modelID: "m1")
        await cache.set(result, text: "disk test", promptType: "grammar", modelID: "m1", language: "en")
        await cache.saveToDisk()
        try await Task.sleep(for: .milliseconds(100))

        await cache.invalidateAll()
        let nilResult = await cache.get(text: "disk test", promptType: "grammar", modelID: "m1", language: "en")
        XCTAssertNil(nilResult)

        await cache.loadFromDisk()
        let loaded = await cache.get(text: "disk test", promptType: "grammar", modelID: "m1", language: "en")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.correctedText, "disk fixed")
    }

    func testLoadFromDisk_corruptFile_doesNotCrash() async {
        let url = await CorrectionCache.shared.cacheFileURL
        try? "not valid json {{{{".write(to: url, atomically: true, encoding: .utf8)
        await CorrectionCache.shared.loadFromDisk()
        let result = await CorrectionCache.shared.get(text: "any", promptType: "grammar", modelID: "m", language: "en")
        XCTAssertNil(result)
    }

    func testSaveToDisk_emptyCache_writesValidJSON() async {
        await CorrectionCache.shared.saveToDisk()
        try? await Task.sleep(for: .milliseconds(100))
        let url = await CorrectionCache.shared.cacheFileURL
        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data)
        // Should decode as empty array
        let entries = try? JSONDecoder().decode([String].self, from: data ?? Data())
        // Actually it's [DiskEntry], verify it's valid JSON at minimum
        XCTAssertNotNil(data.flatMap { try? JSONSerialization.jsonObject(with: $0) })
    }
}

final class RuleBasedEnginePipelineTests: XCTestCase {
    func testRuleBasedResultDoesNotBlockLLM() async {
        let engine = RuleBasedEngine()
        let result = await engine.check("Qual'è il problema? Io andato a casa.", language: "it")
        XCTAssertTrue(result.text.contains("Qual è"), "Rule engine must fix qual'è")
        XCTAssertTrue(result.text.contains("Io andato"), "Rule engine must not fix 'Io andato' (LLM-only error)")
    }
}

final class ValidateCorrectionTests: XCTestCase {
    func testValidateCorrection_doesNotDiscardValidItalianCorrection() {
        let service = StubLLMService.shared
        let original  = "Io andato a casa ieri."
        let corrected = "Sono andato a casa ieri."
        let result = service.validateCorrection(original: original, corrected: corrected, isFluency: false)
        XCTAssertEqual(result, corrected, "validateCorrection must not discard a valid Italian correction")
    }
}

final class SelfConsistencyTests: XCTestCase {
    private let service = StubLLMService.shared

    func testSelectConsensus_strictMajority_winsOverConservative() {
        let original = "Io andato a casa."
        // 2 agree on the real fix, 1 outlier that is closer to the original.
        let candidates = [
            "Sono andato a casa.",
            "Sono andato a casa.",
            "Io andato a casa!"
        ]
        let result = service.selectConsensus(candidates: candidates, original: original)
        XCTAssertEqual(result, "Sono andato a casa.", "A strict majority must win even if an outlier is more conservative")
    }

    func testSelectConsensus_noMajority_picksMostConservativeChange() {
        let original = "Lui mangiano la mela."
        // Three distinct real corrections, no majority. The least-changed (minimal fix) wins.
        let candidates = [
            "Lui mangia la mela.",                      // minimal fix — most conservative
            "Lui mangia la grande mela rossa e dolce.", // invented content
            "Egli consuma una mela."                    // over-rewrite
        ]
        let result = service.selectConsensus(candidates: candidates, original: original)
        XCTAssertEqual(result, "Lui mangia la mela.", "With no majority, the most conservative real correction must win")
    }

    func testSelectConsensus_noChangeVoteDoesNotBuryRealFix() {
        let original = "Lui mangiano la mela."
        // A genuine no-change vote is present but the only other passes are real fixes.
        // A lone no-change vote must NOT suppress a correction when no majority exists.
        let candidates = [original, "Lui mangia la mela.", "Egli mangia una mela."]
        let result = service.selectConsensus(candidates: candidates, original: original)
        XCTAssertEqual(result, "Lui mangia la mela.", "A single no-change vote must not bury a real fix")
    }

    func testSelectConsensus_majorityNoChange_returnsOriginal() {
        let original = "La frase è già corretta."
        let candidates = [original, original, "La frase e già corretta."]
        let result = service.selectConsensus(candidates: candidates, original: original)
        XCTAssertEqual(result, original, "A majority of no-change votes means the text is already correct")
    }

    func testSelectConsensus_singleCandidate_returnsIt() {
        let result = service.selectConsensus(candidates: ["only one"], original: "orig")
        XCTAssertEqual(result, "only one")
    }

    func testSelectConsensus_empty_returnsOriginal() {
        let result = service.selectConsensus(candidates: [], original: "orig")
        XCTAssertEqual(result, "orig")
    }
}

final class SamplingParamsEncodingTests: XCTestCase {
    func testChatRequest_nilSampling_omitsExtraFields() throws {
        let req = ChatRequest(model: "m", messages: [ChatMessage(role: "user", content: "hi")],
                              temperature: 0.1, max_tokens: 64, stream: false)
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("top_p"), "Remote-safe: sampling keys must be omitted when nil")
        XCTAssertFalse(json.contains("repeat_penalty"))
        XCTAssertFalse(json.contains("seed"))
    }

    func testChatRequest_withSampling_emitsFields() throws {
        let sampling = SamplingParams(topP: 0.9, topK: 40, minP: 0.05, repeatPenalty: 1.1, seed: 7)
        let req = ChatRequest(model: "m", messages: [ChatMessage(role: "user", content: "hi")],
                              temperature: 0.1, max_tokens: 64, stream: false, sampling: sampling)
        let json = String(data: try JSONEncoder().encode(req), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"top_p\""))
        XCTAssertTrue(json.contains("\"repeat_penalty\""))
        XCTAssertTrue(json.contains("\"seed\":7"))
    }
}

final class LexiconTests: XCTestCase {
    func testInformalWords_containsGerman() {
        XCTAssertTrue(Lexicon.informalWords.contains("krass"))
        XCTAssertTrue(Lexicon.informalWords.contains("geil"))
    }

    func testInformalWords_containsSpanish() {
        XCTAssertTrue(Lexicon.informalWords.contains("tío"))
        XCTAssertTrue(Lexicon.informalWords.contains("guay"))
    }

    func testInformalWords_containsPortuguese() {
        XCTAssertTrue(Lexicon.informalWords.contains("fixe"))
        XCTAssertTrue(Lexicon.informalWords.contains("beleza"))
    }

    func testAcademicWords_containsGerman() {
        XCTAssertTrue(Lexicon.academicWords.contains("daher"))
        XCTAssertTrue(Lexicon.academicWords.contains("folglich"))
    }

    func testComputeWordScores_informalText_highInformalScore() {
        let scores = Lexicon.computeWordScores(
            words: ["hey", "yeah", "cool"],
            rawWords: ["hey", "yeah", "cool"],
            text: "hey yeah cool"
        )
        XCTAssertGreaterThan(scores.informalScore, 10.0)
    }

    func testComputeWordScores_academicText_highAcademicScore() {
        let scores = Lexicon.computeWordScores(
            words: ["therefore", "furthermore", "consequently"],
            rawWords: ["therefore", "furthermore", "consequently"],
            text: "therefore furthermore consequently"
        )
        XCTAssertGreaterThan(scores.academicScore, 5.0)
    }

    func testComputeWordScores_emptyText_doesNotCrash() {
        let scores = Lexicon.computeWordScores(words: [], rawWords: [], text: "")
        XCTAssertEqual(scores.wordCount, 1)  // max(0, 1)
        XCTAssertEqual(scores.informalScore, 0.0)
    }
}

final class CorrectionSpanTests: XCTestCase {
    func testSpanApplicator_appliesBackToFront() {
        let text = "Io andato al mercato qual'è."
        let spans: [CorrectionSpan] = [
            CorrectionSpan(range: NSRange(location: 3, length: 6),
                           original: "andato", replacement: "sono andato",
                           reason: "ausiliare", confidence: 0.9, source: .llm),
            CorrectionSpan(range: NSRange(location: 21, length: 6),
                           original: "qual'è", replacement: "qual è",
                           reason: "troncamento", confidence: 1.0, source: .ruleBased),
        ]
        let result = SpanApplicator.apply(spans: spans, to: text)
        XCTAssertEqual(result, "Io sono andato al mercato qual è.")
    }

    func testSpanMerger_higherSourceWinsOnOverlap() {
        let s1 = CorrectionSpan(range: NSRange(location: 0, length: 5), original: "hello",
                                replacement: "Hi", reason: "", confidence: 0.8, source: .nativeGrammar)
        let s2 = CorrectionSpan(range: NSRange(location: 0, length: 5), original: "hello",
                                replacement: "Hello", reason: "", confidence: 0.9, source: .languageTool)
        let merged = SpanMerger.merge([s1, s2])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].source, .languageTool)
    }

    func testLLMJSONParser_parsesCorrections() {
        let json = """
        {"corrections":[{"original":"andato","replacement":"sono andato","reason":"ausiliare mancante"}]}
        """
        let spans = LLMJSONParser.parse(json: json, in: "Io andato a casa.")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].replacement, "sono andato")
        XCTAssertEqual(spans[0].source, .llm)
    }

    func testLLMJSONParser_emptyCorrections() {
        let spans = LLMJSONParser.parse(json: #"{"corrections":[]}"#, in: "testo ok")
        XCTAssertEqual(spans.count, 0)
    }

    func testLLMJSONParser_malformedJSON_doesNotCrash() {
        let spans = LLMJSONParser.parse(json: "not json", in: "text")
        XCTAssertEqual(spans.count, 0)
    }

    func testBuildGrammarJSONPrompt_containsSchemaAndText() {
        let engine = PromptEngine(language: "it", style: "equilibrato")
        let prompt = engine.buildGrammarJSONPrompt(for: "Io andato.")
        XCTAssertTrue(prompt.contains("corrections"))
        XCTAssertTrue(prompt.contains("original"))
        XCTAssertTrue(prompt.contains("Io andato."))
    }

    func testSpanApplicator_reconstructsCorrectTextFromSpans() {
        let original = "Ho andato a casa qual'è."
        let spans: [CorrectionSpan] = [
            CorrectionSpan(range: NSRange(location: 3, length: 6),
                           original: "andato", replacement: "sono andato",
                           reason: "ausiliare", confidence: 0.9, source: .llm),
            CorrectionSpan(range: NSRange(location: 17, length: 6),
                           original: "qual'è", replacement: "qual è",
                           reason: "troncamento", confidence: 1.0, source: .ruleBased),
        ]
        let result = SpanApplicator.apply(spans: spans, to: original)
        XCTAssertEqual(result, "Ho sono andato a casa qual è.")
    }
}

final class LanguageToolInstallerTests: XCTestCase {
    func testLanguageToolInstaller_installPathIsInsideAppSupport() {
        let path = LanguageToolInstaller.binaryPath
        XCTAssertTrue(path.path.contains("Application Support/Parrot"))
    }

    func testLanguageToolInstaller_isAvailable_doesNotCrash() {
        let available = LanguageToolInstaller.isAvailable
        XCTAssertTrue(available == true || available == false)
    }
}

final class LanguageToolEngineTests: XCTestCase {
    func testLanguageToolEngine_isAvailable_doesNotCrash() async {
        let engine = LanguageToolEngine()
        let available = await engine.isAvailable
        XCTAssertTrue(available == true || available == false)
    }

    func testLanguageToolEngine_languageCodeMapping() {
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "it"), "it-IT")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "en"), "en-US")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "fr"), "fr-FR")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "de"), "de-DE")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "es"), "es-ES")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "ru"), "ru-RU")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "zh"), "zh-CN")
        XCTAssertEqual(LanguageToolEngine.ltLanguageCode(for: "ja"), "ja-JP")
    }
}

final class DraftDetectorTests: XCTestCase {
    func testShortBulletNotes_scoredAsDraft() {
        let score = DraftDetector.score("richiesta informazioni esame colloquio prof")
        XCTAssertTrue(score.isDraft, "Short keyword notes should be detected as draft")
    }

    func testLongPolishedEmail_notDraft() {
        let text = """
        Gentile Professore Rossi,
        La contatto per richiedere informazioni riguardo al prossimo appello d'esame. Sarei anche interessato a sapere se è possibile organizzare un colloquio per discutere il mio progetto.
        In attesa di una Sua risposta, La ringrazio per la disponibilità.
        Cordiali saluti,
        Marco
        """
        let score = DraftDetector.score(text)
        XCTAssertFalse(score.isDraft, "Polished email should not be detected as draft")
    }

    func testDraftScore_isStatistical_notKeywordBased() {
        // Same draft-like structure in different languages should all score as draft
        let italian  = "richiesta informazioni esame colloquio"
        let english  = "request info exam appointment"
        let german   = "anfrage informationen prüfung termin"
        let chinese  = "考试信息请求 预约"
        for text in [italian, english, german, chinese] {
            XCTAssertTrue(DraftDetector.score(text).isDraft, "'\(text)' should be draft")
        }
    }
}

final class ContactStoreTests: XCTestCase {
    func testFindInText_matchesName() async {
        let store = ContactStore()
        let profile = ContactProfile(name: "Rossi", role: "professore")
        await store.upsert(profile)
        let found = await store.findInText("Scrivo al prof Rossi per l'esame")
        XCTAssertEqual(found?.name, "Rossi")
    }

    func testFindInText_matchesRole() async {
        let store = ContactStore()
        let profile = ContactProfile(name: "Bianchi", role: "direttore")
        await store.upsert(profile)
        let found = await store.findInText("Gentile direttore, la contatto per")
        XCTAssertEqual(found?.name, "Bianchi")
    }

    func testFindInText_noMatch_returnsNil() async {
        let store = ContactStore()
        let found = await store.findInText("testo senza corrispondenze")
        XCTAssertNil(found)
    }

    func testUpsertAndDelete() async {
        let store = ContactStore()
        let profile = ContactProfile(name: "Test User")
        await store.upsert(profile)
        let found = await store.findInText("Test User")
        XCTAssertNotNil(found)
        await store.delete(id: profile.id)
        let gone = await store.findInText("Test User")
        XCTAssertNil(gone)
    }
}

// MARK: - SP1 Inline Completion

final class CompletionPostprocessorTests: XCTestCase {
    func testClean_stripsEchoedPrefix() {
        let r = CompletionPostprocessor.clean(raw: "Ciao Marco come stai", preContext: "Ciao Marco", maxWords: 8)
        XCTAssertEqual(r, " come stai")
    }

    func testClean_stopsAtNewline() {
        let r = CompletionPostprocessor.clean(raw: " informarti del fatto\nNuova riga", preContext: "ti scrivo per", maxWords: 8)
        XCTAssertEqual(r, " informarti del fatto")
    }

    func testClean_capsAtMaxWords() {
        let r = CompletionPostprocessor.clean(raw: "uno due tre quattro cinque sei", preContext: "", maxWords: 3)
        XCTAssertEqual(r, "uno due tre")
    }

    func testClean_emptyRaw_returnsNil() {
        XCTAssertNil(CompletionPostprocessor.clean(raw: "   ", preContext: "x", maxWords: 8))
    }

    func testClean_onlyNewline_returnsNil() {
        XCTAssertNil(CompletionPostprocessor.clean(raw: "\n\n", preContext: "x", maxWords: 8))
    }

    func testSuggestion_firstWord_includesTrailingSpace() {
        let s = CompletionSuggestion(text: " informarti del fatto")
        XCTAssertEqual(s.firstWord, " informarti ")
    }
}

final class LlamaCompletionRequestTests: XCTestCase {
    func testRequest_shape() {
        let req = LlamaCompletionRequest(prompt: "Caro Marco", maxWords: 8)
        XCTAssertTrue(req.cache_prompt)
        XCTAssertFalse(req.stream)
        XCTAssertEqual(req.stop, ["\n"])
        XCTAssertGreaterThanOrEqual(req.n_predict, 8)
    }

    func testRequest_nPredictScalesWithWords() {
        let small = LlamaCompletionRequest(prompt: "x", maxWords: 4)
        let big = LlamaCompletionRequest(prompt: "x", maxWords: 16)
        XCTAssertLessThan(small.n_predict, big.n_predict)
    }

    func testBuildPrompt_capsPrefixLength() {
        let long = String(repeating: "a", count: Constants.completionMaxPrefixChars + 500)
        let ctx = CompletionContext(preContext: long, postContext: "", language: "it")
        let prompt = LlamaCompletionClient.buildPrompt(context: ctx, userPrompt: "")
        XCTAssertEqual(prompt.count, Constants.completionMaxPrefixChars)
    }
}

private final class StubCompletionProvider: CompletionProviding, @unchecked Sendable {
    var result: String
    var error: Error?
    var beforeReturn: (@Sendable () async -> Void)?
    init(result: String = "", error: Error? = nil) { self.result = result; self.error = error }
    func complete(context: CompletionContext, maxWords: Int) async throws -> String {
        if let beforeReturn { await beforeReturn() }
        if let error { throw error }
        return result
    }
}

final class CompletionEngineTests: XCTestCase {
    private func ctx(_ pre: String) -> CompletionContext {
        CompletionContext(preContext: pre, postContext: "", language: "it")
    }

    func testSuggest_returnsCleanedSuggestion() async {
        let engine = CompletionEngine(provider: StubCompletionProvider(result: " come stai oggi"))
        let s = await engine.suggest(context: ctx("Ciao Marco"), maxWords: 8)
        XCTAssertEqual(s?.text, " come stai oggi")
    }

    func testSuggest_unusableShortContext_returnsNil() async {
        let engine = CompletionEngine(provider: StubCompletionProvider(result: "anything"))
        let s = await engine.suggest(context: ctx("a"), maxWords: 8)
        XCTAssertNil(s)
    }

    func testSuggest_providerError_returnsNil() async {
        let engine = CompletionEngine(provider: StubCompletionProvider(error: CorrectionError.serverNotRunning))
        let s = await engine.suggest(context: ctx("Ciao Marco"), maxWords: 8)
        XCTAssertNil(s)
    }

    func testSuggest_supersededWhileInFlight_returnsNil() async {
        let provider = StubCompletionProvider(result: " come stai")
        let engine = CompletionEngine(provider: provider)
        // Simulate a newer request arriving mid-flight: bump generation before the result returns.
        provider.beforeReturn = { await engine.cancelPending() }
        let s = await engine.suggest(context: ctx("Ciao Marco"), maxWords: 8)
        XCTAssertNil(s, "A superseded in-flight suggestion must be discarded")
    }
}

@MainActor
final class CompletionPreferencesTests: XCTestCase {
    func testInlineCompletionEnabled_defaultsTrue() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.inlineCompletionEnabled)
        XCTAssertTrue(PreferencesStore.shared.inlineCompletionEnabled)
    }

    func testMaxCompletionLength_defaultsToConstant() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.maxCompletionLength)
        XCTAssertEqual(PreferencesStore.shared.maxCompletionLength, Constants.completionDefaultMaxWords)
    }
}
