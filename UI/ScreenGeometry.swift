import AppKit

/// Screen math shared by every floating panel (suggestion panel, hover popup, toast, overlays).
///
/// Two coordinate spaces are in play:
///   - **AX** (Accessibility API, CGWindow): origin at the TOP-left of the PRIMARY screen, y grows down.
///   - **AppKit** (NSWindow/NSScreen/NSEvent.mouseLocation): origin at the BOTTOM-left of the
///     PRIMARY screen, y grows up.
/// Both are global across displays and anchored to the primary screen (the one with the menu bar,
/// `NSScreen.screens.first`), so conversion only needs the primary screen's height. Secondary
/// screens can have negative or non-zero origins in either space.
///
/// The pure functions take frames as values so they are testable without real displays; the
/// `@MainActor` wrappers below bind them to `NSScreen`.
enum ScreenGeometry {

    /// Converts an AX rect (top-left origin, y down) to AppKit (bottom-left origin, y up).
    static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the frame that shows most of `rect` (largest intersection area). A rect that
    /// straddles two screens goes to the one holding the bigger part. Zero-area rects (a caret
    /// or a point) fall back to containment of their midpoint. `nil` when nothing matches.
    static func bestFrameIndex(for rect: CGRect, in frames: [CGRect]) -> Int? {
        let areas = frames.map { frame -> CGFloat in
            let overlap = frame.intersection(rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 {
            return best
        }
        return frameIndex(containing: CGPoint(x: rect.midX, y: rect.midY), in: frames)
    }

    /// Index of the frame containing `point`. Edges are inclusive so a point on the top/right
    /// border (e.g. the mouse at the very top of a screen) still resolves to that screen.
    static func frameIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// Moves `frame` (size unchanged) so it lies inside `bounds`. Works for any origin, including
    /// negative ones on secondary displays. When `frame` is larger than `bounds`, it is pinned to
    /// the left and TOP edges so the panel's header and controls stay reachable.
    static func clamp(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        let x = max(bounds.minX, min(bounds.maxX - frame.width, frame.minX))
        let y = min(bounds.maxY - frame.height, max(bounds.minY, frame.minY))
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }
}

// MARK: - NSScreen bindings

@MainActor
extension ScreenGeometry {

    /// The primary (menu-bar) screen. AppKit and AX global coordinates are anchored to it.
    static var primaryScreen: NSScreen? { NSScreen.screens.first }

    /// Converts an AX rect to AppKit using the PRIMARY screen height (never `NSScreen.main`, which
    /// is the screen with the key window and gives wrong results on multi-display setups).
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        appKitRect(fromAX: rect, primaryScreenHeight: primaryScreen?.frame.height ?? 0)
    }

    /// Screen showing most of the AppKit-space `rect`, falling back to the primary screen.
    static func screen(for rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        return bestFrameIndex(for: rect, in: screens.map(\.frame)).map { screens[$0] } ?? primaryScreen
    }

    /// Screen containing the AppKit-space `point`, falling back to the primary screen.
    static func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return frameIndex(containing: point, in: screens.map(\.frame)).map { screens[$0] } ?? primaryScreen
    }

    /// Clamps `frame` into the visible frame of the screen that shows most of `anchor`
    /// (the thing the panel is attached to). Returns `frame` unchanged when no screen exists.
    static func clamp(_ frame: CGRect, toScreenFor anchor: CGRect) -> CGRect {
        guard let visible = screen(for: anchor)?.visibleFrame else { return frame }
        return clamp(frame, into: visible)
    }
}
