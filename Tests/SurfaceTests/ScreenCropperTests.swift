import XCTest
import CoreGraphics
@testable import Parrot

final class ScreenCropperTests: XCTestCase {
    // Window 100×200 pts at origin; image is 2× (200×400 px). All in top-left origin.
    func testCaretInMiddleCropsUpperHalf() {
        let crop = ScreenCropper.cropAboveCaret(
            windowBounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            caretRectTopLeft: CGRect(x: 10, y: 100, width: 1, height: 14),
            imageSize: CGSize(width: 200, height: 400))
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testCaretNearTopReturnsNil() {
        // Nothing meaningful above the caret.
        let crop = ScreenCropper.cropAboveCaret(
            windowBounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            caretRectTopLeft: CGRect(x: 10, y: 3, width: 1, height: 14),
            imageSize: CGSize(width: 200, height: 400))
        XCTAssertNil(crop)
    }

    func testWindowOffsetAccountedFor() {
        // Window not at screen origin: caret 50pt below the window's top.
        let crop = ScreenCropper.cropAboveCaret(
            windowBounds: CGRect(x: 300, y: 200, width: 100, height: 200),
            caretRectTopLeft: CGRect(x: 310, y: 250, width: 1, height: 14),
            imageSize: CGSize(width: 100, height: 200))
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testClampsToImageHeight() {
        let crop = ScreenCropper.cropAboveCaret(
            windowBounds: CGRect(x: 0, y: 0, width: 100, height: 200),
            caretRectTopLeft: CGRect(x: 10, y: 500, width: 1, height: 14),   // caret below window
            imageSize: CGSize(width: 100, height: 200))
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 100, height: 200))
    }

    func testZeroSizeGuards() {
        XCTAssertNil(ScreenCropper.cropAboveCaret(
            windowBounds: .zero,
            caretRectTopLeft: CGRect(x: 0, y: 50, width: 1, height: 14),
            imageSize: CGSize(width: 100, height: 200)))
    }
}
