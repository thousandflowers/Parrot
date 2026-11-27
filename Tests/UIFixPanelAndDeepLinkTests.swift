import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Parrot

@MainActor
final class UIFixKeyablePanelTests: XCTestCase {

    private func makePanel() -> KeyablePanel {
        KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    }

    private func keyEvent(_ keyCode: Int, _ chars: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, characters: chars,
                                       charactersIgnoringModifiers: chars, isARepeat: false,
                                       keyCode: UInt16(keyCode)))
    }

    func testBorderlessNonActivatingPanel_canBecomeKeyButNotMain() {
        let panel = makePanel()
        XCTAssertTrue(panel.canBecomeKey, "Return/Esc shortcuts need a key window")
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel), "target app must stay active")
    }

    func testEscape_invokesOnCancel() throws {
        let panel = makePanel()
        var cancelled = 0
        panel.onCancel = { cancelled += 1 }
        panel.keyDown(with: try keyEvent(kVK_Escape, "\u{1b}"))
        panel.cancelOperation(nil)
        XCTAssertEqual(cancelled, 2)
    }

    func testOtherKeys_doNotCancel() throws {
        let panel = makePanel()
        var cancelled = false
        panel.onCancel = { cancelled = true }
        panel.keyDown(with: try keyEvent(kVK_ANSI_A, "a"))
        XCTAssertFalse(cancelled)
    }

    func testRelinquishKeyFocus_isNoOpWhenNotKey() {
        let panel = makePanel()
        panel.relinquishKeyFocus()
        XCTAssertFalse(panel.isVisible, "a panel that was never shown must not be ordered in")
    }
}

final class UIFixDeepLinkTests: XCTestCase {

    private func url(_ s: String) throws -> URL { try XCTUnwrap(URL(string: s)) }

    func testLiteralPercentSequenceIsNotDecodedTwice() throws {
        // User text "100%41" arrives encoded as 100%2541. One decode → "100%41"; a second would give "100A".
        let link = try CorrectionDeepLink.parse(url("parrot://correct?text=100%2541"))
        XCTAssertEqual(link.text, "100%41")
    }

    func testBarePercentInTextIsKept() throws {
        // "50% off" — a second removingPercentEncoding returns nil and used to drop the request.
        let link = try CorrectionDeepLink.parse(url("parrot://correct?text=50%25%20off"))
        XCTAssertEqual(link.text, "50% off")
        XCTAssertEqual(link.promptType, .grammar)
    }

    func testModeSelectsPromptType() throws {
        XCTAssertEqual(try CorrectionDeepLink.parse(url("parrot://correct?text=hi&mode=fluency")).promptType, .fluency)
        XCTAssertEqual(try CorrectionDeepLink.parse(url("parrot://correct?text=hi&mode=translate")).promptType,
                       .translation(targetLanguage: "en"))
    }

    func testRejectsOtherHostsSchemesAndMissingText() throws {
        XCTAssertThrowsError(try CorrectionDeepLink.parse(url("parrot://settings?text=hi"))) {
            XCTAssertEqual($0 as? CorrectionDeepLink.ParseError, .notACorrectionLink)
        }
        XCTAssertThrowsError(try CorrectionDeepLink.parse(url("wren://correct?text=hi")))
        XCTAssertThrowsError(try CorrectionDeepLink.parse(url("parrot://correct?text="))) {
            XCTAssertEqual($0 as? CorrectionDeepLink.ParseError, .missingText)
        }
    }

    func testLengthCap() throws {
        let atLimit = String(repeating: "a", count: maxDeepLinkTextLength)
        XCTAssertNoThrow(try CorrectionDeepLink.parse(url("parrot://correct?text=\(atLimit)")))
        XCTAssertThrowsError(try CorrectionDeepLink.parse(url("parrot://correct?text=\(atLimit)a"))) {
            XCTAssertEqual($0 as? CorrectionDeepLink.ParseError,
                           .textTooLong(length: maxDeepLinkTextLength + 1, limit: maxDeepLinkTextLength))
        }
    }
}

/// The Accessibility alert is shown by both apps, so no localization may hardcode a product name.
final class UIFixAccessibilityAlertStringsTests: XCTestCase {

    private var resourcesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    private func tables() throws -> [(lang: String, strings: [String: String])] {
        let dirs = try FileManager.default.contentsOfDirectory(at: resourcesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        return try dirs.compactMap { dir in
            let file = dir.appendingPathComponent("Localizable.strings")
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let dict = try XCTUnwrap(NSDictionary(contentsOf: file) as? [String: String], "unparsable \(file.path)")
            return (dir.deletingPathExtension().lastPathComponent, dict)
        }
    }

    func testEveryTableWithTheAlertUsesAnAppNameFormat() throws {
        let withAlert = try tables().filter { $0.strings["alert.accessibility.title"] != nil }
        XCTAssertFalse(withAlert.isEmpty)
        for table in withAlert {
            XCTAssertNil(table.strings["alert.accessibility.body"], "\(table.lang): stale hardcoded body key")
            let body = try XCTUnwrap(table.strings["alert.accessibility.body_format"], "\(table.lang): missing body_format")
            for mode in AppMode.allCases {
                let rendered = String(format: body, mode.displayName)
                XCTAssertTrue(rendered.contains(mode.displayName), "\(table.lang)")
                for other in AppMode.allCases where other != mode {
                    XCTAssertFalse(rendered.contains(other.displayName), "\(table.lang): names \(other.displayName)")
                }
            }
        }
    }
}
