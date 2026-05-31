import XCTest
@testable import Parrot

final class SuggestionCacheTests: XCTestCase {
    func testHitReturnsStoredValue() {
        let cache = SuggestionCache(capacity: 2)
        cache.set(contextHash: "a", suggestion: "hello")
        XCTAssertEqual(cache.get(contextHash: "a"), "hello")
    }

    func testMissReturnsNil() {
        let cache = SuggestionCache(capacity: 2)
        XCTAssertNil(cache.get(contextHash: "nope"))
    }

    func testLRUEvictsLeastRecentlyUsed() {
        let cache = SuggestionCache(capacity: 2)
        cache.set(contextHash: "a", suggestion: "A")
        cache.set(contextHash: "b", suggestion: "B")
        _ = cache.get(contextHash: "a")               // touch a → b is now LRU
        cache.set(contextHash: "c", suggestion: "C")  // evicts b
        XCTAssertEqual(cache.get(contextHash: "a"), "A")
        XCTAssertNil(cache.get(contextHash: "b"))
        XCTAssertEqual(cache.get(contextHash: "c"), "C")
    }
}
