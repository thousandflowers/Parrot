import Foundation

/// Picks the best TextSurface backend for the focused pid by *trying* them in order and
/// observing what each can do — never by matching the bundle identifier.
///
/// Order: NativeAX → (if Chromium process and native was blind) ChromiumAX → Universal.
/// Universal always succeeds (typed-input buffer), so `select` is total.
final class SurfaceProbe {
    private let makeNative: (pid_t) -> TextSurface
    private let makeChromium: (pid_t) -> TextSurface
    private let makeUniversal: (pid_t) -> TextSurface
    private let isChromium: (pid_t) -> Bool

    init(makeNative: @escaping (pid_t) -> TextSurface,
         makeChromium: @escaping (pid_t) -> TextSurface,
         makeUniversal: @escaping (pid_t) -> TextSurface,
         isChromium: @escaping (pid_t) -> Bool) {
        self.makeNative = makeNative
        self.makeChromium = makeChromium
        self.makeUniversal = makeUniversal
        self.isChromium = isChromium
    }

    func select(pid: pid_t) -> TextSurface {
        let native = makeNative(pid)
        if native.readContext() != nil { return native }
        if isChromium(pid) {
            let chromium = makeChromium(pid)      // applies AXManualAccessibility in its init
            if chromium.readContext() != nil { return chromium }
        }
        return makeUniversal(pid)
    }
}
