import XCTest
@testable import Parrot

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

    func test_retriesOnceWhenFirstIsEmpty() async {
        let stub = StubProvider(["", "ciao mondo"])
        let engine = CompletionEngine(provider: stub)
        let ctx = CompletionContext(preContext: "scrivo una ", postContext: "", language: "it")
        let s = await engine.suggest(context: ctx, maxWords: 4, allowCode: false, midWord: false)
        XCTAssertNotNil(s)
        let n = await stub.callCount()
        XCTAssertEqual(n, 2)   // first empty → one retry
    }
}
