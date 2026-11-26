import XCTest
@testable import Parrot

/// Output sanitizing / validation of raw model output (validateCorrection, postProcess).
final class PipelineFixSanitizerTests: XCTestCase {
    private let service = StubLLMService.shared

    // MARK: - Structural strips must not eat the user's own structure

    func testLabelPrefix_typoInsideUserPrefix_isKept() {
        let original = "Cioa Marco: come stai oggi?"
        let corrected = "Ciao Marco: come stai oggi?"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: corrected), corrected)
    }

    func testLabelPrefix_modelLabel_isStripped() {
        let original = "Io andato a casa ieri."
        let raw = "Testo corretto: Sono andato a casa ieri."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri.")
    }

    func testLabelPrefix_modelLabelStackedOnUserLabel_isStripped() {
        let original = "Nota: compra il late domani."
        let raw = "Corrected text: Nota: compra il latte domani."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Nota: compra il latte domani.")
    }

    func testWrappingQuotes_userQuotes_areKept() {
        let original = "\"Ciao\" disse \"adio\""
        let corrected = "\"Ciao\" disse \"addio\""
        XCTAssertEqual(service.validateCorrection(original: original, corrected: corrected), corrected)
    }

    func testWrappingQuotes_modelQuotes_areStripped() {
        let original = "Io andato a casa ieri."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: "\"Sono andato a casa ieri.\""),
                       "Sono andato a casa ieri.")
    }

    func testSecondParagraph_presentInOriginal_isKept() {
        let original = "Ciao Marco, come stai oggi?\n\nIo andato."
        let corrected = "Ciao Marco, come stai oggi?\n\nSono andato."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: corrected), corrected)
    }

    func testTrailingCommentary_singleParagraphOriginal_isStripped() {
        let original = "Io andato a casa ieri sera."
        let raw = "Sono andato a casa ieri sera.\n\nHo corretto."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri sera.")
    }

    // MARK: - Garbage wrappers

    func testCodeFence_isStripped() {
        let original = "Io andato a casa ieri."
        let raw = "```text\nSono andato a casa ieri.\n```"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri.")
    }

    func testThinkBlock_isStripped() {
        let original = "Io andato a casa ieri."
        let raw = "<think>The verb needs an auxiliary.</think>\nSono andato a casa ieri."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri.")
    }

    func testDanglingCloseThink_keepsOnlyAnswer() {
        let original = "Io andato a casa ieri."
        let raw = "The verb needs an auxiliary.</think>\n\nSono andato a casa ieri."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri.")
    }

    func testUnterminatedThink_returnsOriginal() {
        let original = "Io andato a casa ieri."
        let raw = "<think>The verb needs an auxiliary, so I will"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), original)
    }

    func testColonlessPreamble_isStripped() {
        let original = "Io andato a casa ieri sera."
        let raw = "Here is the corrected text\nSono andato a casa ieri sera."
        XCTAssertEqual(service.validateCorrection(original: original, corrected: raw), "Sono andato a casa ieri sera.")
    }

    // MARK: - Language / script handling

    func testLanguageCompare_usesPrimarySubtag() {
        let original = "我今天去学校了，天气很好"
        let corrected = "我今天去了学校，天气很好"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: corrected, language: "zh"), corrected)
    }

    func testCJKSingleEdit_isNotTreatedAsFullRewrite() {
        XCTAssertLessThan(CorrectionSanitizer.wordChangeFraction(original: "我今天去学校了。", corrected: "我今天去學校了。"), 0.5)
        let original = "我今天去学校了"
        let corrected = "我今天去學校了"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: corrected), corrected)
    }

    func testWordChangeFraction_latin_unchanged() {
        XCTAssertEqual(CorrectionSanitizer.wordChangeFraction(original: "Io andato a casa", corrected: "Io andato a casa"), 0)
        XCTAssertEqual(CorrectionSanitizer.wordChangeFraction(original: "a b c d", corrected: "a b x y"), 0.5, accuracy: 0.001)
    }

    // MARK: - Truncation

    func testGrammar_truncatedOutput_returnsOriginal() {
        // 40% of the words dropped (passes the >50% word-change guard) but only 58% of the length left.
        let original = "casa rana luna sole mare vela neve pane vino olio."
        let truncated = "casa rana luna sole mare vela"
        XCTAssertEqual(service.validateCorrection(original: original, corrected: truncated), original)
    }

    func testParseChatResponse_flagsLengthFinishReason() throws {
        let json = #"{"choices":[{"message":{"content":"Sono andato"},"finish_reason":"length"}]}"#
        let parsed = try service.parseChatResponse(data: Data(json.utf8))
        XCTAssertEqual(parsed.content, "Sono andato")
        XCTAssertTrue(parsed.isTruncated)
    }

    func testParseChatResponse_stopIsNotTruncated() throws {
        let json = #"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#
        XCTAssertFalse(try service.parseChatResponse(data: Data(json.utf8)).isTruncated)
        let noReason = #"{"choices":[{"message":{"content":"ok"}}]}"#
        XCTAssertFalse(try service.parseChatResponse(data: Data(noReason.utf8)).isTruncated)
    }

    // MARK: - postProcess routes by prompt type

    func testPostProcess_translation_isNotRejectedByGrammarRules() {
        let text = "Ciao, come stai oggi?"
        let translated = "Hello, how are you today?"
        XCTAssertEqual(service.postProcess(raw: translated, text: text, promptType: .translation(targetLanguage: "en"), lang: "it"),
                       translated)
    }

    func testPostProcess_custom_stripsThinkAndFence() {
        let text = "Ciao"
        let raw = "<think>hmm</think>\n```\nCiao a tutti\n```"
        XCTAssertEqual(service.postProcess(raw: raw, text: text, promptType: .custom(name: "x", template: "{{TEXT}}"), lang: "it"),
                       "Ciao a tutti")
    }

    // MARK: - Token budget

    func testTokenEstimate_CJK_isAtLeastOnePerCharacter() {
        let cjk = String(repeating: "我今天去学校了", count: 40)
        XCTAssertGreaterThanOrEqual(TokenEstimator.estimatedTokens(for: cjk), cjk.count)
        XCTAssertGreaterThanOrEqual(TokenEstimator.estimatedTokens(for: "hello world, this is a test"), 27 / 4)
    }
}
