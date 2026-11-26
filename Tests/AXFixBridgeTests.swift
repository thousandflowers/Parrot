import XCTest
import CoreGraphics
@testable import Parrot

/// Pure helpers extracted from AccessibilityBridge / RealtimeMonitor / TabInterceptor fixes.
final class AXFixBridgeTests: XCTestCase {

    // MARK: Write-target verification (wrong-document write guard)

    func testWriteTargetMatchesOriginalAtRange() {
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "Hello wrld, bye", range: CFRange(location: 6, length: 4), expected: "wrld")
        XCTAssertEqual(r, .match)
    }

    func testWriteTargetMismatchWhenFieldChanged() {
        // Same app, different tab/field: the range now covers other text.
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "Totally other doc", range: CFRange(location: 6, length: 4), expected: "wrld")
        XCTAssertEqual(r, .mismatch)
    }

    func testWriteTargetMismatchWhenRangePastEnd() {
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "short", range: CFRange(location: 3, length: 10), expected: nil)
        XCTAssertEqual(r, .mismatch)
    }

    func testWriteTargetBoundsOnlyWhenNoExpectedText() {
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "anything here", range: CFRange(location: 0, length: 8), expected: nil)
        XCTAssertEqual(r, .match)
    }

    func testWriteTargetUnreadable() {
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: nil, range: CFRange(location: 0, length: 1), expected: "x")
        XCTAssertEqual(r, .unreadable)
    }

    func testWriteTargetToleratesTrimmedOriginal() {
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "  a line  \nnext", range: CFRange(location: 0, length: 10), expected: "a line")
        XCTAssertEqual(r, .match)
    }

    func testWriteTargetUsesUTF16Offsets() {
        // "😀" is 2 UTF-16 units; AX ranges are UTF-16 based.
        let r = AccessibilityBridge.checkWriteTarget(
            fieldValue: "😀 teh", range: CFRange(location: 3, length: 3), expected: "teh")
        XCTAssertEqual(r, .match)
    }

    func testSelectionTarget() {
        XCTAssertEqual(AccessibilityBridge.checkSelectionTarget(selectedText: "abc", expected: "abc"), .match)
        XCTAssertEqual(AccessibilityBridge.checkSelectionTarget(selectedText: "xyz", expected: "abc"), .mismatch)
        XCTAssertEqual(AccessibilityBridge.checkSelectionTarget(selectedText: "", expected: "abc"), .unreadable)
        XCTAssertEqual(AccessibilityBridge.checkSelectionTarget(selectedText: nil, expected: nil), .match)
    }

    // MARK: AX → AppKit flip uses the primary screen height

    func testFlipAXRectToAppKit() {
        let ax = CGRect(x: 100, y: 50, width: 10, height: 20)
        let flipped = AccessibilityBridge.flipAXRectToAppKit(ax, primaryScreenHeight: 1000)
        XCTAssertEqual(flipped, CGRect(x: 100, y: 930, width: 10, height: 20))
    }

    // MARK: Synthetic typing

    func testUnicodeChunksRespectLimit() {
        let text = String(repeating: "a", count: 45)
        let chunks = AccessibilityBridge.unicodeChunks(text, maxUnits: 20)
        XCTAssertEqual(chunks.map(\.count), [20, 20, 5])
        XCTAssertEqual(String(utf16CodeUnits: chunks.flatMap { $0 }, count: 45), text)
    }

    func testUnicodeChunksNeverSplitSurrogatePairs() {
        // 19 ASCII + emoji (2 units): the emoji must move to the next chunk whole.
        let text = String(repeating: "b", count: 19) + "😀" + "c"
        let chunks = AccessibilityBridge.unicodeChunks(text, maxUnits: 20)
        XCTAssertEqual(chunks.map(\.count), [19, 3])
        for chunk in chunks {
            XCTAssertNotNil(String(utf16CodeUnits: chunk, count: chunk.count).unicodeScalars.first)
            XCTAssertFalse(UTF16.isLeadSurrogate(chunk.last!), "chunk ends mid surrogate pair")
        }
        let rejoined = chunks.flatMap { $0 }
        XCTAssertEqual(String(utf16CodeUnits: rejoined, count: rejoined.count), text)
    }

    func testUnicodeChunksSplitsOversizeClusterByScalar() {
        // A ZWJ family sequence longer than the limit is split at scalar boundaries only.
        let family = "👨‍👩‍👧‍👦"   // 11 UTF-16 units
        let chunks = AccessibilityBridge.unicodeChunks(family, maxUnits: 4)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 4 })
        XCTAssertTrue(chunks.allSatisfy { !UTF16.isLeadSurrogate($0.last!) })
        let rejoined = chunks.flatMap { $0 }
        XCTAssertEqual(String(utf16CodeUnits: rejoined, count: rejoined.count), family)
    }

    func testUnicodeChunksEmpty() {
        XCTAssertTrue(AccessibilityBridge.unicodeChunks("", maxUnits: 20).isEmpty)
    }

    func testTargetFrontmost() {
        XCTAssertTrue(AccessibilityBridge.isTargetFrontmost(frontPID: 42, target: 42))
        XCTAssertFalse(AccessibilityBridge.isTargetFrontmost(frontPID: 7, target: 42))
        XCTAssertFalse(AccessibilityBridge.isTargetFrontmost(frontPID: nil, target: 42))
        XCTAssertFalse(AccessibilityBridge.isTargetFrontmost(frontPID: 0, target: 0))
    }

    // MARK: Clipboard

    func testClipboardRestoreDelayLongerForElectron() {
        XCTAssertGreaterThan(AccessibilityBridge.clipboardRestoreDelay(isElectron: true),
                             AccessibilityBridge.clipboardRestoreDelay(isElectron: false))
    }

    func testRemoveLegacyClipboardStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AXFixTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("clipboard_state.json")
        try Data("[]".utf8).write(to: file)
        AccessibilityBridge.removeLegacyClipboardStateFile(at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        AccessibilityBridge.removeLegacyClipboardStateFile(at: file)   // idempotent, no throw
    }

    // MARK: RealtimeMonitor observer policy

    func testObserverStaysForCompletionWhenRealtimeOff() {
        XCTAssertTrue(RealtimeMonitor.shouldObserve(realtimeCorrection: false, inlineCompletion: true))
        XCTAssertTrue(RealtimeMonitor.shouldObserve(realtimeCorrection: true, inlineCompletion: false))
        XCTAssertFalse(RealtimeMonitor.shouldObserve(realtimeCorrection: false, inlineCompletion: false))
    }

    // MARK: TabInterceptor backslash accept

    func testBackslashAcceptIgnoresCommandAndControl() {
        XCTAssertTrue(isBackslashAccept(typedCharacter: "\\", flags: []))
        // Italian layout produces "\" with ⌥⇧ — must still accept.
        XCTAssertTrue(isBackslashAccept(typedCharacter: "\\", flags: [.maskAlternate, .maskShift]))
        XCTAssertFalse(isBackslashAccept(typedCharacter: "\\", flags: .maskCommand))
        XCTAssertFalse(isBackslashAccept(typedCharacter: "\\", flags: .maskControl))
        XCTAssertFalse(isBackslashAccept(typedCharacter: "a", flags: []))
        XCTAssertFalse(isBackslashAccept(typedCharacter: nil, flags: []))
    }
}
