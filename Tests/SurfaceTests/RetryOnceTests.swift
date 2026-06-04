import XCTest
@testable import Parrot

/// Verifies CompletionEngine behaviour around empty/failed results.
/// Retry was intentionally removed (comment in CompletionEngine.swift) — single attempt only,
/// empty response from the provider returns nil rather than retrying.
final class RetryOnceTests: XCTestCase {
    actor StubProvider: CompletionProviding {
        var calls = 0
        let outputs: [String]
        init(_ o: [String]) { outputs = o }
        func complete(context: CompletionContext, maxWords: Int) async throws -> String {
            defer { calls += 1 }
            return calls < outputs.count ? outputs[calls] : ""
        }
        func callCount() -> Int { calls }
    }

    func test_emptyFirst_returnsNil() async {
        let stub = StubProvider(["", "ciao mondo"])
        let engine = CompletionEngine(provider: stub)
        let ctx = CompletionContext(preContext: "scrivo una ", postContext: "", language: "it")
        let s = await engine.suggest(context: ctx, maxWords: 4, allowCode: false, midWord: false)
        // Single attempt — first result empty → returns nil, does not retry.
        XCTAssertNil(s)
        let n = await stub.callCount()
        XCTAssertEqual(n, 1)
    }

    func test_nonEmpty_returnsSuggestion() async {
        let stub = StubProvider(["ciao mondo"])
        let engine = CompletionEngine(provider: stub)
        let ctx = CompletionContext(preContext: "scrivo una ", postContext: "", language: "it")
        let s = await engine.suggest(context: ctx, maxWords: 4, allowCode: false, midWord: false)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.text, "ciao mondo")
        let n = await stub.callCount()
        XCTAssertEqual(n, 1)
    }
}
