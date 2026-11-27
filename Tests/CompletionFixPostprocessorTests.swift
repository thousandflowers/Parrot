import XCTest
import AppKit
@testable import Parrot

/// Finding 10: in mid-word mode the postprocessor stripped the model's leading space even when the
/// "incomplete" trailing word was really a finished name/abbreviation the spell checker doesn't know
/// ("Thx" + " for" → "Thxfor").
final class CompletionFixPostprocessorTests: XCTestCase {
    /// These cases need the system spell server to reject a non-word. When it is overloaded
    /// (parallel test runs) `checkSpelling` times out and reports "no misspelling" for anything,
    /// which says nothing about the postprocessor. Probe with a guaranteed non-word first.
    private func requireResponsiveSpellServer() throws {
        let r = NSSpellChecker.shared.checkSpelling(of: "qzxvbnwk", startingAt: 0, language: "en",
                                                    wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        try XCTSkipIf(r.location == NSNotFound, "NSSpellServer unresponsive (timed out)")
    }

    func testMidWord_keepsModelSpace_whenGluedResultIsNotAWord() throws {
        try requireResponsiveSpellServer()
        let r = CompletionPostprocessor.clean(raw: " for the help", preContext: "Thx", maxWords: 4, midWord: true)
        XCTAssertEqual(r, " for the help")
    }

    func testMidWord_keepsModelSpace_afterUnknownName() throws {
        try requireResponsiveSpellServer()
        let r = CompletionPostprocessor.clean(raw: " and Marco", preContext: "Ciao a Eugenio", maxWords: 3, midWord: true)
        XCTAssertEqual(r, " and Marco")
    }

    func testMidWord_stillGlues_whenGluedResultIsAWord() {
        let r = CompletionPostprocessor.clean(raw: " ption", preContext: "rece", maxWords: 4, midWord: true)
        XCTAssertEqual(r, "ption")
    }

    func testMidWord_shortTrailingFragment_stillGlues() {
        // Below the minimum trailing-word length the model's space is not trusted: continue the token.
        let r = CompletionPostprocessor.clean(raw: " ccavo", preContext: "Io non mi se", maxWords: 3, midWord: true)
        XCTAssertEqual(r, "ccavo")
    }

    func testMidWord_noModelSpace_glues() {
        let r = CompletionPostprocessor.clean(raw: "ption desk", preContext: "I went to the rece", maxWords: 4, midWord: true)
        XCTAssertEqual(r, "ption desk")
    }

    func testCandidateLanguages_shortContextUsesOnlyPreferredPrimaries() {
        XCTAssertEqual(WordBoundary.candidateLanguages(context: "rece", preferred: ["it-IT", "en-US", "it"]), ["it", "en"])
    }

    func testCandidateLanguages_longContextPutsDetectedFirst() {
        let langs = WordBoundary.candidateLanguages(
            context: "Ciao Marco, ci vediamo domani al solito posto per il caffè", preferred: ["en-US"])
        XCTAssertEqual(langs, ["it", "en"])
    }
}
