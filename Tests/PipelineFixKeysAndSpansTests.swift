import XCTest
@testable import Parrot

/// Cache identity, language comparison and span coordinate spaces.
final class PipelineFixKeysAndSpansTests: XCTestCase {

    // MARK: - Cache key

    func testCacheKey_differentCustomPrompts_differ() {
        let a = PromptType.custom(name: "Formal", template: "Make formal: {{TEXT}}")
        let b = PromptType.custom(name: "Casual", template: "Make casual: {{TEXT}}")
        XCTAssertNotEqual(a.cacheKey(extraInstruction: nil), b.cacheKey(extraInstruction: nil))
    }

    func testCacheKey_isStableAndIncludesExtraInstruction() {
        let a = PromptType.custom(name: "Formal", template: "Make formal: {{TEXT}}")
        XCTAssertEqual(a.cacheKey(extraInstruction: nil), a.cacheKey(extraInstruction: nil))
        XCTAssertNotEqual(PromptType.grammar.cacheKey(extraInstruction: nil),
                          PromptType.grammar.cacheKey(extraInstruction: "Glossary: Parrot"))
        XCTAssertEqual(PromptType.grammar.cacheKey(extraInstruction: nil), "grammar",
                       "built-in keys must stay equal to the label so persisted entries stay valid")
        // SHA-256 based, so the value is identical across launches.
        XCTAssertEqual(StableHash.hex("abc"), "ba7816bf8f01cfea")
    }

    func testCache_customPromptsDoNotCollide() async {
        await CorrectionCache.shared.invalidateAll()
        let a = PromptType.custom(name: "A", template: "A {{TEXT}}").cacheKey(extraInstruction: nil)
        let b = PromptType.custom(name: "B", template: "B {{TEXT}}").cacheKey(extraInstruction: nil)
        let result = CorrectionResult(original: "x", corrected: "A-result", modelID: "m", promptType: "custom")
        await CorrectionCache.shared.set(result, text: "x", promptType: a, modelID: "m", language: "en")
        let hit = await CorrectionCache.shared.get(text: "x", promptType: b, modelID: "m", language: "en")
        XCTAssertNil(hit)
    }

    // MARK: - Language

    func testIsSameLanguage_comparesPrimarySubtags() {
        XCTAssertTrue(LanguageDetector.isSameLanguage("zh", "zh-Hans"))
        XCTAssertTrue(LanguageDetector.isSameLanguage("en_US", "en"))
        XCTAssertFalse(LanguageDetector.isSameLanguage("it", "es"))
    }

    func testDetect_shortConfidentItalian_beatsEnglishFallback() {
        XCTAssertEqual(LanguageDetector.detect(text: "Ciao, come stai?", fallbackLanguage: "en"), "it")
    }

    func testDetect_shortAmbiguous_keepsFallback() {
        XCTAssertEqual(LanguageDetector.detect(text: "I has a cat", fallbackLanguage: "en"), "en")
        XCTAssertEqual(LanguageDetector.detect(text: "hi", fallbackLanguage: "fr"), "fr")
    }

    // MARK: - Spans

    func testRuleSpans_repeatedMatch_eachInItsOwnPlace() async {
        let text = "Un pò di pane e un pò di vino"
        let spans = await RuleBasedEngine.shared.spans(in: text, language: "it")
        let ns = text as NSString
        let poSpans = spans.filter { $0.original == "un pò" || $0.original == "Un pò" }
        XCTAssertEqual(poSpans.count, 1, "rule is case-sensitive: only the lowercase occurrence matches")
        let lower = ns.range(of: "un pò", options: [], range: NSRange(location: 1, length: ns.length - 1))
        XCTAssertEqual(poSpans.first?.range, lower)
    }

    func testRuleSpans_sameFixTwice_distinctRanges() async {
        let text = "Ok , va bene , grazie"
        let spans = await RuleBasedEngine.shared.spans(in: text, language: "it")
        let ranges = spans.map(\.range.location)
        XCTAssertEqual(Set(ranges).count, ranges.count, "each occurrence must get its own range")
        XCTAssertEqual(spans.count, 2)
        for span in spans {
            XCTAssertEqual((text as NSString).substring(with: span.range), span.original)
        }
    }

    func testHarperScalarOffsets_convertToUTF16() {
        // "😀 teh" — Harper counts the emoji as ONE char; UTF-16 counts it as two units.
        let text = "😀 teh cat"
        let range = HarperEngine.utf16Range(scalarStart: 2, scalarLength: 3, in: text)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "teh")
        XCTAssertNil(HarperEngine.utf16Range(scalarStart: 50, scalarLength: 3, in: text))
    }
}
