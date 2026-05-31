import CoreGraphics

/// The "every app" guarantee. Reads context from keys the user typed (no AX, no clipboard) and
/// inserts via synthesized keystrokes, which work in any editable field. Caret rect comes from an
/// injected provider and may be nil, in which case the controller shows a floating hint instead of
/// inline ghost text.
final class UniversalSurface: TextSurface {
    private let buffer: TypedInputBuffer
    private let doInsert: (String) -> Void
    private let caretProvider: () -> CGRect?

    init(buffer: TypedInputBuffer,
         doInsert: @escaping (String) -> Void,
         caretProvider: @escaping () -> CGRect?) {
        self.buffer = buffer
        self.doInsert = doInsert
        self.caretProvider = caretProvider
    }

    func readContext() -> SurfaceContext? {
        let pre = buffer.preContext
        return pre.isEmpty ? nil : SurfaceContext(pre: pre, post: "")
    }

    func caretRect() -> CGRect? { caretProvider() }

    func insert(_ text: String) {
        doInsert(text)
        for c in text { buffer.type(character: c) }   // keep buffer consistent with the field
    }

    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard buffer.preContext.hasSuffix(wrong) else { return false }
        // Production doInsert deletes `wrong` via a control prefix before typing; here we model
        // the buffer side effect (delete wrong, type replacement) plus the insert closure.
        for _ in 0..<wrong.count { buffer.deleteBackward() }
        doInsert(replacement)
        for c in replacement { buffer.type(character: c) }
        return true
    }
}
