import XCTest
import CoreGraphics
@testable import Parrot

final class SurfaceProbeTests: XCTestCase {
    private func surface(_ canRead: Bool, _ hasCaret: Bool) -> TextSurface {
        final class S: TextSurface {
            let r: Bool; let c: Bool
            init(_ r: Bool, _ c: Bool) { self.r = r; self.c = c }
            func readContext() -> SurfaceContext? { r ? SurfaceContext(pre: "x", post: "") : nil }
            func caretRect() -> CGRect? { c ? .init(x: 0, y: 0, width: 0, height: 1) : nil }
            func insert(_ t: String) {}
            func replaceLastWord(wrong: String, with replacement: String) -> Bool { false }
        }
        return S(canRead, hasCaret)
    }

    func testPrefersNativeWhenItCanRead() {
        let probe = SurfaceProbe(
            makeNative: { _ in self.surface(true, true) },
            makeChromium: { _ in self.surface(true, true) },
            makeUniversal: { _ in self.surface(true, false) },
            isChromium: { _ in false }
        )
        let chosen = probe.select(pid: 123)
        XCTAssertNotNil(chosen.readContext())   // native picked, can read
    }

    func testFallsBackToChromiumForChromiumProcessWhenNativeBlind() {
        var chromiumTried = false
        let probe = SurfaceProbe(
            makeNative: { _ in self.surface(false, false) },          // native blind
            makeChromium: { _ in chromiumTried = true; return self.surface(true, true) },
            makeUniversal: { _ in self.surface(true, false) },
            isChromium: { _ in true }
        )
        _ = probe.select(pid: 123)
        XCTAssertTrue(chromiumTried)
    }

    func testFallsBackToUniversalWhenAllAXBlind() {
        let probe = SurfaceProbe(
            makeNative: { _ in self.surface(false, false) },
            makeChromium: { _ in self.surface(false, false) },
            makeUniversal: { _ in self.surface(true, false) },        // universal always reads (typed buffer)
            isChromium: { _ in true }
        )
        let chosen = probe.select(pid: 123)
        XCTAssertNotNil(chosen.readContext())
        XCTAssertNil(chosen.caretRect())        // universal: degraded caret
    }
}
