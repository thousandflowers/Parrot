import XCTest
@testable import Parrot

final class AdaptiveDebounceTests: XCTestCase {
    func testIdleUsesCategoryFloor() {
        let d = AdaptiveDebounce(maxMs: 200)
        // Long pause → fire fast at the per-domain floor (native 80, terminal 50).
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 1000, category: .native), 80)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 1000, category: .terminal), 50)
    }

    func testFastTypingGrowsDelay() {
        let d = AdaptiveDebounce(maxMs: 200)
        let fast = d.nextDelayMs(sinceLastKeystrokeMs: 20, category: .native)   // hammering keys
        XCTAssertGreaterThan(fast, 80)                                          // above the native floor
        XCTAssertLessThanOrEqual(fast, 200)
    }

    func testNeverExceedsMax() {
        let d = AdaptiveDebounce(maxMs: 200)
        XCTAssertEqual(d.nextDelayMs(sinceLastKeystrokeMs: 0, category: .native), 200)
    }
}
