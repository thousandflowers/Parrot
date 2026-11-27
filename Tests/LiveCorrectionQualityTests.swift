import XCTest
@testable import Parrot

/// Live quality check against a real llama-server (opt-in, skipped in CI):
///   PARROT_LIVE_LLM_PORT=11499 swift test --filter LiveCorrectionQualityTests
/// Runs the app's own grammar path (prompt, sampling, self-consistency, sanitizer) and checks the
/// product rules: the error gets fixed, nothing else is rewritten, no preamble/quotes leak.
final class LiveCorrectionQualityTests: XCTestCase {
    private struct Case {
        let text: String
        let language: String
        let mustContain: [String]
        let mustNotContain: [String]
    }

    private let cases: [Case] = [
        Case(text: "I has a apple and she dont like it.", language: "en",
             mustContain: ["have", "an apple", "doesn't"], mustNotContain: ["has a apple", "dont"]),
        Case(text: "Their going to the store tomorow.", language: "en",
             mustContain: ["tomorrow"], mustNotContain: ["tomorow", "Their going"]),
        Case(text: "Ieri sono andato al mare con i miei amici, ci siamo divertiti molto.", language: "it",
             mustContain: ["Ieri sono andato al mare con i miei amici, ci siamo divertiti molto."],
             mustNotContain: ["divertito"]),   // already correct: must come back verbatim
        Case(text: "Domani vado a la stazione perche ho perso il treno.", language: "it",
             mustContain: ["alla stazione", "perché"], mustNotContain: ["a la stazione"]),
        Case(text: "Se avrei saputo, sarei venuto prima.", language: "it",
             mustContain: ["Se avessi saputo"], mustNotContain: ["Se avrei"]),
    ]

    func testGrammarCorrectionsOnRealModel() async throws {
        guard let port = ProcessInfo.processInfo.environment["PARROT_LIVE_LLM_PORT"], !port.isEmpty else {
            throw XCTSkip("set PARROT_LIVE_LLM_PORT to run against a live llama-server")
        }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/chat/completions"))
        let preambles = ["here is", "corrected text", "sure", "certo", "ecco"]
        let only = ProcessInfo.processInfo.environment["PARROT_LIVE_CASE"] ?? ""
        for c in cases where only.isEmpty || c.text.contains(only) {
            let result = try await LocalLLMService.shared.performCorrection(
                text: c.text, promptType: .grammar, language: c.language,
                model: "live", url: url, apiKey: nil,
                sampling: Constants.localGrammarSampling, samples: Constants.localSelfConsistencyPasses)
            let out = result.correctedText
            print("LIVE [\(c.language)] \(c.text)\n  → \(out)")
            for s in c.mustContain { XCTAssertTrue(out.contains(s), "missing '\(s)' in: \(out)") }
            for s in c.mustNotContain { XCTAssertFalse(out.contains(s), "still has '\(s)' in: \(out)") }
            XCTAssertFalse(preambles.contains { out.lowercased().hasPrefix($0) }, "preamble leaked: \(out)")
            XCTAssertFalse(out.hasPrefix("\"") && !c.text.hasPrefix("\""), "quotes added: \(out)")
            XCTAssertLessThan(out.count, c.text.count * 2, "rewrote/expanded: \(out)")
        }
    }
}
