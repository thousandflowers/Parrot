import XCTest
import CoreGraphics
@testable import Parrot

final class UniversalSurfaceTests: XCTestCase {
    func testReadsFromTypedBuffer() {
        let buf = TypedInputBuffer()
        for c in "draf" { buf.type(character: c) }
        let s = UniversalSurface(buffer: buf, doInsert: { _ in }, caretProvider: { nil })
        XCTAssertEqual(s.readContext(), SurfaceContext(pre: "draf", post: ""))
    }

    func testInsertGoesThroughKeystrokeAndUpdatesBuffer() {
        let buf = TypedInputBuffer()
        for c in "he" { buf.type(character: c) }
        var inserted = ""
        let s = UniversalSurface(buffer: buf, doInsert: { inserted += $0 }, caretProvider: { nil })
        s.insert("llo")
        XCTAssertEqual(inserted, "llo")
        XCTAssertEqual(s.readContext()?.pre, "hello")   // buffer reflects accepted text
    }

    func testReplaceLastWordAbortsOnMismatch() {
        let buf = TypedInputBuffer()
        for c in "say wrld" { buf.type(character: c) }
        let s = UniversalSurface(buffer: buf, doInsert: { _ in }, caretProvider: { nil })
        XCTAssertFalse(s.replaceLastWord(wrong: "world", with: "world"))
    }

    func testReplaceLastWordRewritesBufferOnMatch() {
        let buf = TypedInputBuffer()
        for c in "say wrld" { buf.type(character: c) }
        var inserted = ""
        let s = UniversalSurface(buffer: buf, doInsert: { inserted += $0 }, caretProvider: { nil })
        XCTAssertTrue(s.replaceLastWord(wrong: "wrld", with: "world"))
        XCTAssertEqual(s.readContext()?.pre, "say world")
        XCTAssertEqual(inserted, "world")
    }

    func testCaretFromProvider() {
        let s = UniversalSurface(buffer: TypedInputBuffer(),
                                 doInsert: { _ in },
                                 caretProvider: { CGRect(x: 9, y: 9, width: 0, height: 11) })
        XCTAssertEqual(s.caretRect(), CGRect(x: 9, y: 9, width: 0, height: 11))
    }
}
