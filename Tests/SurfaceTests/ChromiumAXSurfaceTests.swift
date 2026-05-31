import XCTest
import CoreGraphics
@testable import Parrot

final class ChromiumAXSurfaceTests: XCTestCase {
    func testSetsManualAccessibilityOnceBeforeRead() {
        var flagCalls = 0
        let s = ChromiumAXSurface(
            pid: 1,
            enableManualAX: { flagCalls += 1 },
            read: { (pre: "hi", post: "", caret: CGRect(x: 0, y: 0, width: 0, height: 10), secure: false) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertEqual(flagCalls, 1)                 // flag set in init
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "hi", post: ""))
        _ = s.readContext()
        XCTAssertEqual(flagCalls, 1)                 // never re-set
    }
}
