import XCTest
import CoreGraphics
@testable import Parrot

final class CompatibilityProbeTests: XCTestCase {
    private func ctx(pre: String, post: String, secure: Bool) -> CompletionAXContext {
        CompletionAXContext(preContext: pre, postContext: post, caretRect: .zero, isSecure: secure)
    }

    func test_readableField_isFull() {
        XCTAssertEqual(CompatibilityProbe.classify(context: ctx(pre: "ciao ", post: "", secure: false), focused: true), .full)
    }

    func test_secureField_isSecure() {
        XCTAssertEqual(CompatibilityProbe.classify(context: ctx(pre: "", post: "", secure: true), focused: true), .secureField)
    }

    func test_emptyButReadable_isFull() {
        XCTAssertEqual(CompatibilityProbe.classify(context: ctx(pre: "", post: "", secure: false), focused: true), .full)
    }

    func test_noContext_butFieldFocused_isTypedOnly() {
        XCTAssertEqual(CompatibilityProbe.classify(context: nil, focused: true), .typedOnly)
    }

    func test_noContext_noFocus_isNoFocus() {
        XCTAssertEqual(CompatibilityProbe.classify(context: nil, focused: false), .noFocus)
    }

    func test_probe_usesContextProvider() async {
        let result = await CompatibilityProbe.probe(
            pid: 123,
            contextProvider: { _ in self.ctx(pre: "hello", post: "", secure: false) },
            hasFocusedField: { _ in false }
        )
        XCTAssertEqual(result, .full)
    }
}
