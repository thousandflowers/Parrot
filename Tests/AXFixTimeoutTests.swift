import XCTest
@testable import Parrot

final class AXFixTimeoutTests: XCTestCase {
    /// The old task-group version waited for the hung work before returning, so it never
    /// actually timed out. The caller must resume at the deadline.
    func testTimeoutReturnsPromptlyWhileWorkIsStillRunning() async {
        let start = Date()
        let r = await withAXTimeout(milliseconds: 30) { () -> Int in
            Thread.sleep(forTimeInterval: 1.0)   // hung AX call
            return 1
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertNil(r)
        XCTAssertLessThan(elapsed, 0.5, "withAXTimeout waited for the hung work")
    }

    func testFastWorkWinsAndReturnsValue() async {
        let start = Date()
        let r = await withAXTimeout(milliseconds: 2_000) { "ok" }
        XCTAssertEqual(r, "ok")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }

    func testOptionalResultPassesThrough() async {
        let r: Int?? = await withAXTimeout(milliseconds: 500) { Optional<Int>.none }
        XCTAssertEqual(r, .some(nil))
    }
}
