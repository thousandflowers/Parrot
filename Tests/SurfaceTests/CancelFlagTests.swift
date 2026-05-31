import XCTest
@testable import Parrot

final class CancelFlagTests: XCTestCase {
    func testStartsLive() { XCTAssertFalse(CancelFlag().isCancelled) }
    func testCancelSticks() {
        let f = CancelFlag(); f.cancel()
        XCTAssertTrue(f.isCancelled)
    }
}
