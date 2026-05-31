import CoreGraphics

/// Text around the caret in the focused field.
struct SurfaceContext: Equatable {
    let pre: String
    let post: String
}

/// What a backend can do for the current focus. Decided by observation, never by bundle ID.
struct SurfaceCapabilities: Equatable {
    let canRead: Bool
    let canInsert: Bool
    let hasCaretRect: Bool
}

/// Single interface for reading context, locating the caret, and writing text into the
/// focused field. Backends: NativeAXSurface, ChromiumAXSurface, UniversalSurface.
protocol TextSurface: AnyObject {
    func readContext() -> SurfaceContext?
    func caretRect() -> CGRect?
    func insert(_ text: String)
    /// Returns false (and makes no change) if `wrong` is not the current trailing word.
    @discardableResult
    func replaceLastWord(wrong: String, with replacement: String) -> Bool
}
