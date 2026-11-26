import XCTest
@testable import Parrot

/// Finding 4: after a full accept the cached suggestion for the pre-insert context must be evicted,
/// otherwise a stale AX read re-serves the identical ghost and a second Tab double-inserts it.
final class CompletionFixCacheTests: XCTestCase {
    func testRemove_evictsEntry() {
        let cache = SuggestionCache(capacity: 4)
        cache.set(contextHash: "Hello wor", suggestion: "ld")
        cache.remove(contextHash: "Hello wor")
        XCTAssertNil(cache.get(contextHash: "Hello wor"))
    }

    func testRemove_unknownKey_isNoOp() {
        let cache = SuggestionCache(capacity: 4)
        cache.set(contextHash: "a", suggestion: "A")
        cache.remove(contextHash: "missing")
        XCTAssertEqual(cache.get(contextHash: "a"), "A")
    }

    func testRemove_freesCapacitySlot() {
        let cache = SuggestionCache(capacity: 2)
        cache.set(contextHash: "a", suggestion: "A")
        cache.set(contextHash: "b", suggestion: "B")
        cache.remove(contextHash: "a")
        cache.set(contextHash: "c", suggestion: "C")   // must NOT evict b: a's slot was freed
        XCTAssertEqual(cache.get(contextHash: "b"), "B")
        XCTAssertEqual(cache.get(contextHash: "c"), "C")
    }
}
