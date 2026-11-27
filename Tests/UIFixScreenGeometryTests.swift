import XCTest
@testable import Parrot

/// Pure screen math, exercised with synthetic display layouts (no real NSScreen).
final class UIFixScreenGeometryTests: XCTestCase {

    // Primary 1440×900 at the origin; a 1920×1080 display to its LEFT and slightly BELOW
    // (negative x and y), and one 2560×1440 ABOVE the primary (positive y beyond 900).
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let left = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
    private let above = CGRect(x: 0, y: 900, width: 2560, height: 1440)
    private var layout: [CGRect] { [primary, left, above] }

    // MARK: - AX → AppKit

    func testAXToAppKit_onPrimary_flipsAgainstPrimaryHeight() {
        // 20pt-tall selection whose top edge is 100pt below the primary's top.
        let ax = CGRect(x: 50, y: 100, width: 200, height: 20)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: 900)
        XCTAssertEqual(appKit, CGRect(x: 50, y: 780, width: 200, height: 20))
    }

    func testAXToAppKit_onScreenAbovePrimary_hasNegativeAXYAndHighAppKitY() {
        // AX y is negative for a display above the primary; AppKit y must land inside `above`.
        let ax = CGRect(x: 300, y: -500, width: 100, height: 20)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: 900)
        XCTAssertEqual(appKit.minY, 1380)
        XCTAssertTrue(above.contains(appKit))
    }

    func testAXToAppKit_isAnInvolution() {
        let ax = CGRect(x: -800, y: 1000, width: 40, height: 18)
        let once = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: 900)
        XCTAssertEqual(ScreenGeometry.appKitRect(fromAX: once, primaryScreenHeight: 900), ax)
    }

    // MARK: - Screen selection

    func testBestFrame_rectFullyInsideSecondary() {
        let rect = CGRect(x: -1000, y: 100, width: 200, height: 50)
        XCTAssertEqual(ScreenGeometry.bestFrameIndex(for: rect, in: layout), 1)
    }

    func testBestFrame_straddlingRectGoesToLargerOverlap() {
        // 300pt wide, 220pt on the primary and 80pt on the left display. `contains` would fail
        // for both screens; max overlap picks the primary.
        let rect = CGRect(x: -80, y: 400, width: 300, height: 20)
        XCTAssertFalse(primary.contains(rect))
        XCTAssertFalse(left.contains(rect))
        XCTAssertEqual(ScreenGeometry.bestFrameIndex(for: rect, in: layout), 0)
    }

    func testBestFrame_zeroSizeRectUsesPointContainment() {
        let caret = CGRect(x: 500, y: 1200, width: 0, height: 0)
        XCTAssertEqual(ScreenGeometry.bestFrameIndex(for: caret, in: layout), 2)
    }

    func testBestFrame_offEveryScreenReturnsNil() {
        let rect = CGRect(x: 10_000, y: 10_000, width: 10, height: 10)
        XCTAssertNil(ScreenGeometry.bestFrameIndex(for: rect, in: layout))
        XCTAssertNil(ScreenGeometry.bestFrameIndex(for: rect, in: []))
    }

    func testFrameContainingPoint_includesTopAndRightEdges() {
        // NSEvent.mouseLocation can equal maxY at the top edge of a screen.
        XCTAssertEqual(ScreenGeometry.frameIndex(containing: CGPoint(x: 1440, y: 450), in: [primary]), 0)
        XCTAssertEqual(ScreenGeometry.frameIndex(containing: CGPoint(x: 700, y: 900), in: [primary]), 0)
        XCTAssertEqual(ScreenGeometry.frameIndex(containing: CGPoint(x: -1, y: 0), in: layout), 1)
        XCTAssertNil(ScreenGeometry.frameIndex(containing: CGPoint(x: -5000, y: 0), in: layout))
    }

    // MARK: - Clamping

    func testClamp_insideBoundsIsUnchanged() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
        XCTAssertEqual(ScreenGeometry.clamp(frame, into: primary), frame)
    }

    func testClamp_onNegativeOriginScreen_respectsThatScreensEdges() {
        // Visible frame of the left display (minus a dock strip) has negative origin.
        let visible = CGRect(x: -1920, y: -300, width: 1920, height: 1055)
        let pastLeftAndBottom = CGRect(x: -2100, y: -400, width: 300, height: 200)
        let clamped = ScreenGeometry.clamp(pastLeftAndBottom, into: visible)
        XCTAssertEqual(clamped.origin, CGPoint(x: -1920, y: -300))

        let pastRightAndTop = CGRect(x: -100, y: 700, width: 300, height: 200)
        XCTAssertEqual(ScreenGeometry.clamp(pastRightAndTop, into: visible).origin, CGPoint(x: -300, y: 555))
    }

    func testClamp_keepsSize() {
        let frame = CGRect(x: 5000, y: 5000, width: 340, height: 280)
        XCTAssertEqual(ScreenGeometry.clamp(frame, into: primary).size, frame.size)
    }

    func testClamp_tallerThanScreen_pinsTopEdge() {
        let tall = CGRect(x: 0, y: -50, width: 300, height: 1000)
        let clamped = ScreenGeometry.clamp(tall, into: primary)
        XCTAssertEqual(clamped.maxY, primary.maxY, "header must stay on screen")
    }
}
