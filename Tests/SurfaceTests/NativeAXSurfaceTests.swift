import XCTest
import CoreGraphics
@testable import Parrot

final class NativeAXSurfaceTests: XCTestCase {
    func testMapsContextAndCaret() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "foo ", post: "bar", caret: CGRect(x: 5, y: 5, width: 0, height: 12), secure: false) },
            doInsert: { _ in true },
            doReplace: { _, _ in true }
        )
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "foo ", post: "bar"))
        XCTAssertEqual(s.caretRect(), CGRect(x: 5, y: 5, width: 0, height: 12))
    }

    func testSecureFieldReadsNil() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "x", post: "", caret: .zero, secure: true) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertNil(s.readContext())   // never read secure fields
    }

    func testZeroCaretRectIsNil() {
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "x", post: "", caret: .zero, secure: false) },
            doInsert: { _ in true }, doReplace: { _, _ in true })
        XCTAssertNil(s.caretRect())
    }

    func testReplaceAbortsOnMismatch() {
        var replaced = false
        let s = NativeAXSurface(
            pid: 1,
            read: { (pre: "hello wirld", post: "", caret: .zero, secure: false) },
            doInsert: { _ in true },
            doReplace: { _, _ in replaced = true; return true })
        XCTAssertFalse(s.replaceLastWord(wrong: "world", with: "world"))
        XCTAssertFalse(replaced)
        XCTAssertTrue(s.replaceLastWord(wrong: "wirld", with: "world"))
        XCTAssertTrue(replaced)
    }
}
