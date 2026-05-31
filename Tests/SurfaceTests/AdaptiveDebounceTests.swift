import XCTest
@testable import Parrot

final class AdaptiveDebounceTests: XCTestCase {
    func testIdleUsesMinimum() {
        let d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 1000), 40)  // long pause → fast
    }

    func testFastTypingGrowsDelay() {
        let d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        let fast = d.nextDelayMs(sinceLastKeystrokeMs: 20)              // hammering keys
        XCTAssertGreaterThan(fast, 40)
        XCTAssertLessThanOrEqual(fast, 200)
    }

    func testNeverExceedsMax() {
        let d = AdaptiveDebounce(minMs: 40, maxMs: 200)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 0), 200)
    }
}
