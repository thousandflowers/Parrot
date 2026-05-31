import CoreGraphics

/// AX backend for native Cocoa apps. The actual AX calls are injected so the mapping logic is
/// unit-testable; the production wiring (SurfaceProbe.live) passes closures backed by
/// AccessibilityBridge.
final class NativeAXSurface: TextSurface {
    typealias ReadResult = (pre: String, post: String, caret: CGRect, secure: Bool)

    private let pid: pid_t
    private let read: () -> ReadResult?
    private let doInsert: (String) -> Bool
    private let doReplace: (String, String) -> Bool

    init(pid: pid_t,
         read: @escaping () -> ReadResult?,
         doInsert: @escaping (String) -> Bool,
         doReplace: @escaping (String, String) -> Bool) {
        self.pid = pid
        self.read = read
        self.doInsert = doInsert
        self.doReplace = doReplace
    }

    func readContext() -> SurfaceContext? {
        guard let r = read(), !r.secure else { return nil }
        return SurfaceContext(pre: r.pre, post: r.post)
    }

    func caretRect() -> CGRect? {
        guard let r = read(), r.caret != .zero else { return nil }
        return r.caret
    }

    func insert(_ text: String) { _ = doInsert(text) }

    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool {
        guard let r = read(), r.pre.hasSuffix(wrong) else { return false }  // abort on mismatch
        return doReplace(wrong, replacement)
    }
}
