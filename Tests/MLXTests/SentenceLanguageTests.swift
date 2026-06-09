import XCTest
@testable import Parrot

final class SentenceLanguageTests: XCTestCase {
    func testItalianTailAfterEnglishSentence() {
        let text = "The meeting went well. Adesso devo scrivere il resoconto per il"
        XCTAssertEqual(SentenceLanguage.detect(preContext: text, fallback: "en"), "it")
    }

    func testEnglishTailAfterItalianSentence() {
        let text = "Ho finito la prima parte. Now we need to schedule the"
        XCTAssertEqual(SentenceLanguage.detect(preContext: text, fallback: "it"), "en")
    }

    func testMidSentenceCodeSwitchUsesTrailingWindow() {
        // Switch happens inside one sentence: the trailing words decide.
        let text = "Devo chiamare il cliente because the project deadline is"
        XCTAssertEqual(SentenceLanguage.detect(preContext: text, fallback: "it"), "en")
    }

    func testShortFragmentFallsBackToPreference() {
        XCTAssertEqual(SentenceLanguage.detect(preContext: "ok", fallback: "it"), "it")
        XCTAssertEqual(SentenceLanguage.detect(preContext: "", fallback: "en"), "en")
    }

    func testSingleLanguageStaysDetected() {
        let text = "Domani mattina passo in ufficio a prendere i documenti che servono per la"
        XCTAssertEqual(SentenceLanguage.detect(preContext: text, fallback: "en"), "it")
    }

    func testNewlineStartsNewSentence() {
        let text = "Tutto confermato per domani.\nPlease forward this message to the"
        XCTAssertEqual(SentenceLanguage.detect(preContext: text, fallback: "it"), "en")
    }
}
