import CoreGraphics

/// AX backend for Chromium/Electron apps. They ship with AX disabled until a client sets the
/// private `AXManualAccessibility` attribute to true on the app element; after that they expose a
/// real AX tree like a native app. We set the flag once in init, then behave like NativeAXSurface.
final class ChromiumAXSurface: TextSurface {
    typealias ReadResult = NativeAXSurface.ReadResult

    private let read: () -> ReadResult?
    private let doInsert: (String) -> Bool
    private let doReplace: (String, String) -> Bool

    init(pid: pid_t,
         enableManualAX: () -> Void,
         read: @escaping () -> ReadResult?,
         doInsert: @escaping (String) -> Bool,
         doReplace: @escaping (String, String) -> Bool) {
        enableManualAX()                 // force the AX tree on, once
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
        guard let r = read(), r.pre.hasSuffix(wrong) else { return false }
        return doReplace(wrong, replacement)
    }
}
