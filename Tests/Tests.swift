import XCTest
@testable import RefineClone

final class PromptEngineTests: XCTestCase {
    func testBuildGrammarPrompt_containsUserText() {
        let engine = PromptEngine(language: "en", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "This is a test")
        XCTAssertTrue(prompt.contains("This is a test"))
        XCTAssertTrue(prompt.contains("<TEXT>"))
        XCTAssertTrue(prompt.contains("</TEXT>"))
        XCTAssertTrue(prompt.contains("Output only the corrected text; no notes. Do not include <TEXT>/<CUSTOM> tags."))
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

    func testComputeDiff_sameText_returnsEmpty() {
        let ops = CorrectionResult.computeDiff(original: "hello", corrected: "hello")
        XCTAssertNotNil(ops)
        XCTAssertTrue(ops?.isEmpty ?? false)
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
