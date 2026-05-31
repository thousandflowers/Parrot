import XCTest
@testable import Parrot

final class AXTimeoutTests: XCTestCase {
    func testReturnsValueBeforeTimeout() async {
        let r = await withAXTimeout(milliseconds: 100) { 42 }
        XCTAssertEqual(r, 42)
    }

    func testReturnsNilOnTimeout() async {
        let r = await withAXTimeout(milliseconds: 20) { () -> Int in
            Thread.sleep(forTimeInterval: 0.2)   // simulate a hung AX call
            return 1
        }
        XCTAssertNil(r)
    }
}
