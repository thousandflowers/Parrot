import XCTest
@testable import Parrot

final class TypedInputBufferTests: XCTestCase {
    func testAccumulatesTypedCharacters() {
        let buf = TypedInputBuffer()
        for c in "hello" { buf.type(character: c) }
        XCTAssertEqual(buf.preContext, "hello")
    }

    func testBackspaceRemovesLast() {
        let buf = TypedInputBuffer()
        for c in "helo" { buf.type(character: c) }
        buf.deleteBackward()
        buf.type(character: "p")
        XCTAssertEqual(buf.preContext, "help")
    }

    func testNavigationInvalidates() {
        let buf = TypedInputBuffer()
        for c in "hello" { buf.type(character: c) }
        buf.invalidate()                 // arrow key / click / paste / undo
        XCTAssertEqual(buf.preContext, "")
        buf.type(character: "x")
        XCTAssertEqual(buf.preContext, "x")
    }

    func testFocusChangeResets() {
        let buf = TypedInputBuffer()
        for c in "abc" { buf.type(character: c) }
        buf.focusChanged()
        XCTAssertEqual(buf.preContext, "")
    }

    func testCapsToMaxLength() {
        let buf = TypedInputBuffer(maxLength: 4)
        for c in "abcdef" { buf.type(character: c) }
        XCTAssertEqual(buf.preContext, "cdef")   // keeps the tail
    }
}
