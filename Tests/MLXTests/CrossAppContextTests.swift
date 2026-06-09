import XCTest
@testable import Parrot

final class CrossAppContextTests: XCTestCase {
    func testPreviousReturnsOtherAppEntry() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 600)
        let t0 = Date()
        store.record(text: "Email thread about the Q3 budget", bundleID: "com.apple.mail", at: t0)

        let prev = store.previous(excluding: "com.tinyspeck.slackmacgap", now: t0.addingTimeInterval(30))
        XCTAssertEqual(prev?.bundleID, "com.apple.mail")
        XCTAssertEqual(prev?.text, "Email thread about the Q3 budget")
    }

    func testPreviousExcludesCurrentApp() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 600)
        let t0 = Date()
        store.record(text: "Slack thread", bundleID: "com.tinyspeck.slackmacgap", at: t0)

        XCTAssertNil(store.previous(excluding: "com.tinyspeck.slackmacgap", now: t0.addingTimeInterval(5)))
    }

    func testPreviousExpiresAfterTTL() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 600)
        let t0 = Date()
        store.record(text: "Old mail", bundleID: "com.apple.mail", at: t0)

        XCTAssertNil(store.previous(excluding: "com.app.other", now: t0.addingTimeInterval(601)))
    }

    func testPreviousPicksMostRecentOtherApp() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 600)
        let t0 = Date()
        store.record(text: "Mail", bundleID: "com.apple.mail", at: t0)
        store.record(text: "Notes", bundleID: "com.apple.notes", at: t0.addingTimeInterval(60))

        let prev = store.previous(excluding: "com.tinyspeck.slackmacgap", now: t0.addingTimeInterval(90))
        XCTAssertEqual(prev?.bundleID, "com.apple.notes")
    }

    func testRecordCapsTextLength() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 10)
        store.record(text: String(repeating: "x", count: 50), bundleID: "com.apple.mail", at: .now)

        let prev = store.previous(excluding: "other", now: .now)
        XCTAssertEqual(prev?.text.count, 10)
    }

    func testRecordIgnoresEmptyTextAndBundle() {
        var store = CrossAppContextStore(ttl: 600, maxChars: 600)
        store.record(text: "", bundleID: "com.apple.mail", at: .now)
        store.record(text: "hello", bundleID: "", at: .now)

        XCTAssertNil(store.previous(excluding: "other", now: .now))
    }
}
