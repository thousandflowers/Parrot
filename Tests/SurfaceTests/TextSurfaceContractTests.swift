import XCTest
import CoreGraphics
@testable import Parrot

private final class FakeSurface: TextSurface {
    var stored = ""
    let caps: SurfaceCapabilities
    init(caps: SurfaceCapabilities) { self.caps = caps }
    func readContext() -> SurfaceContext? { caps.canRead ? SurfaceContext(pre: stored, post: "") : nil }
    func caretRect() -> CGRect? { caps.hasCaretRect ? CGRect(x: 1, y: 2, width: 0, height: 14) : nil }
    func insert(_ text: String) { stored += text }
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard stored.hasSuffix(wrong) else { return false }
        stored.removeLast(wrong.count); stored += replacement; return true
    }
}

final class TextSurfaceContractTests: XCTestCase {
    func testInsertAppends() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: true, canInsert: true, hasCaretRect: true))
        s.insert("abc")
        XCTAssertEqual(s.readContext()?.pre, "abc")
    }

    func testReplaceLastWordAbortsOnMismatch() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: true, canInsert: true, hasCaretRect: true))
        s.insert("hello wirld")
        XCTAssertFalse(s.replaceLastWord(wrong: "world", with: "world!")) // mismatch → abort
        XCTAssertTrue(s.replaceLastWord(wrong: "wirld", with: "world"))
        XCTAssertEqual(s.readContext()?.pre, "hello world")
    }

    func testBlindSurfaceReturnsNilContext() {
        let s = FakeSurface(caps: SurfaceCapabilities(canRead: false, canInsert: true, hasCaretRect: false))
        XCTAssertNil(s.readContext())
        XCTAssertNil(s.caretRect())
    }
}
