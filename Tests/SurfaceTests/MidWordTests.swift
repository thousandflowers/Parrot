import XCTest
@testable import Parrot

final class MidWordTests: XCTestCase {
    func testMidWordContinuesWithoutSpace() {
        // Caret inside "rece" → continue the word, no boundary space.
        let r = CompletionPostprocessor.clean(raw: "ption desk", preContext: "I went to the rece", maxWords: 4, midWord: true)
        XCTAssertEqual(r, "ption desk")
        XCTAssertEqual("I went to the rece" + (r ?? ""), "I went to the reception desk")
    }

    func testMidWordStripsModelLeadingSpace() {
        let r = CompletionPostprocessor.clean(raw: " ption", preContext: "rece", maxWords: 4, midWord: true)
        XCTAssertEqual(r, "ption")
    }

    func testWordBoundaryStillAddsSpace() {
        // Not mid-word: "per" is a complete word → boundary space.
        let r = CompletionPostprocessor.clean(raw: "chiedere un favore", preContext: "ti scrivo per", maxWords: 8, midWord: false)
        XCTAssertEqual(r, " chiedere un favore")
    }

    @MainActor
    func testIsMidWordDetection() {
        XCTAssertTrue(WordBoundary.isMidWord(preContext: "I went to the rece"))   // "rece" incomplete
        XCTAssertFalse(WordBoundary.isMidWord(preContext: "I think we should "))  // ends with space
        XCTAssertFalse(WordBoundary.isMidWord(preContext: "the reception"))       // complete word
    }

    func test_lastCharLetter_isMidWord() {
        XCTAssertTrue(WordBoundary.isMidWordFast(preContext: "rece"))
        XCTAssertTrue(WordBoundary.isMidWordFast(preContext: "ciao mond"))
    }
    func test_trailingSpaceOrPunct_isBoundary() {
        XCTAssertFalse(WordBoundary.isMidWordFast(preContext: "ciao "))
        XCTAssertFalse(WordBoundary.isMidWordFast(preContext: "ciao,"))
        XCTAssertFalse(WordBoundary.isMidWordFast(preContext: ""))
    }
}
