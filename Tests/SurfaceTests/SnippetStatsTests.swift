import XCTest
@testable import Parrot

final class SnippetMatcherTests: XCTestCase {
    private let snippets = [
        Snippet(abbreviation: "addr", expansion: "123 Main St"),
        Snippet(abbreviation: "sig", expansion: "Best, Eugenio", isEnabled: false),
    ]

    func testMatchesLastWordCaseInsensitive() {
        XCTAssertEqual(SnippetMatcher.match(preContext: "my ADDR", snippets: snippets)?.expansion, "123 Main St")
    }

    func testSkipsDisabledSnippet() {
        XCTAssertNil(SnippetMatcher.match(preContext: "sig", snippets: snippets))
    }

    func testMatchesAtStartOfNewLine() {
        // Regression: split must treat newline as a separator, not glue it to the word.
        XCTAssertEqual(SnippetMatcher.match(preContext: "first line\naddr", snippets: snippets)?.expansion, "123 Main St")
    }

    func testMatchesAfterTab() {
        XCTAssertNotNil(SnippetMatcher.match(preContext: "x\taddr", snippets: snippets))
    }

    func testNoMatchForUnknownWord() {
        XCTAssertNil(SnippetMatcher.match(preContext: "hello world", snippets: snippets))
    }
}

final class StatsStoreSessionTests: XCTestCase {
    func testSessionCountersAreDeltaSinceLoad() async {
        let store = StatsStore.shared
        let base = await store.sessionShown()
        await store.recordShown()
        await store.recordShown()
        let after = await store.sessionShown()
        XCTAssertEqual(after - base, 2, "session counter must report delta, not lifetime total")
    }

    func testSessionAcceptedTracksDelta() async {
        let store = StatsStore.shared
        let base = await store.sessionAccepted()
        await store.recordAccepted(text: "ciao")
        let after = await store.sessionAccepted()
        XCTAssertEqual(after - base, 1)
    }
}
