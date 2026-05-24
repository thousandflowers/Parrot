import AppKit

/// Drives a frame-animated monochromatic bird silhouette in the menu bar status button.
///
/// States map to events:
///   idle       — default, walking leg cycle
///   analyzing  — head-tilt, watching; set when a check starts
///   found      — excited bounce + crest; set when corrections are available
///   ok         — calm settle; set when no changes or correction applied
@MainActor
final class MenuBarBirdAnimator {
    static let shared = MenuBarBirdAnimator()
    private init() {}

    enum BirdState: Equatable { case idle, analyzing, found, ok }

    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var resetTimer: Timer?
    private(set) var state: BirdState = .idle
    private var frame = 0

    // MARK: - Public API

    func attach(to button: NSStatusBarButton) {
        self.button = button
        startTimer()
        renderFrame()
    }

    func setState(_ newState: BirdState) {
        guard state != newState else { return }
        state = newState
        frame = 0
        resetTimer?.invalidate()
        startTimer()
        renderFrame()
        scheduleAutoReset()
    }

    // MARK: - Timer

    private var fps: Double {
        switch state {
        case .idle:      return 8
        case .analyzing: return 6
        case .found:     return 12
        case .ok:        return 3
        }
    }

    private var frameCount: Int {
        switch state {
        case .idle:      return 8
        case .analyzing: return 8
        case .found:     return 8
        case .ok:        return 4
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frame = (self.frame + 1) % self.frameCount
                self.renderFrame()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func scheduleAutoReset() {
        let delay: TimeInterval
        switch state {
        case .ok:    delay = 2.5
        case .found: delay = 6.0
        default: return
        }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.setState(.idle) }
        }
        RunLoop.main.add(t, forMode: .common)
        resetTimer = t
    }

    // MARK: - Rendering

    private func renderFrame() {
        guard let button else { return }
        let s = state, f = frame
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            MenuBarBirdAnimator.drawBird(state: s, frame: f)
            return true
        }
        img.isTemplate = true
        button.image = img
        button.imageScaling = .scaleProportionallyDown
    }

    // MARK: - Bird Drawing
    // Canvas: 18×18 pt, y=0 at bottom (NSImage flipped: false = AppKit standard).
    //
    // Approximate layout (pt):
    //   Feet/legs   y 2–4
    //   Body        y 4–9    (oval, cx=8.5, cy=6.5, w=7.5, h=5)
    //   Tail        extends left from body
    //   Head        y 8.5–13.5 (circle, cx=11, cy=11, r=2.5)
    //   Beak        extends right from head
    //   Crest       y 13.5–17 (found state)

    private static func drawBird(state: BirdState, frame: Int) {
        // Compute per-frame parameters
        var bodyOff: CGFloat = 0    // vertical offset (positive = up)
        var headDX: CGFloat = 0     // head horizontal shift (tilt simulation)
        var crest = false
        var beakOpen = false
        var legPhase = 0

        switch state {
        case .idle:
            let bobs: [CGFloat] = [0, 0.3, 0.5, 0.3, 0, -0.3, -0.3, 0]
            bodyOff = bobs[frame % 8]
            legPhase = frame % 4

        case .analyzing:
            let shifts: [CGFloat] = [0, -0.4, -0.8, -1.0, -0.8, -0.4, 0, 0.4]
            headDX = shifts[frame % 8]

        case .found:
            let jumps: [CGFloat] = [0, 0.7, 1.5, 2.0, 1.5, 0.8, 0.3, 0]
            bodyOff = jumps[frame % 8]
            crest = true
            beakOpen = frame % 3 != 0

        case .ok:
            let settles: [CGFloat] = [0.2, 0, 0.2, 0]
            bodyOff = settles[frame % 4]
        }

        NSColor.black.setFill()

        // ── Body ──────────────────────────────────────────────────────────
        let bx: CGFloat = 8.5
        let by = 6.5 + bodyOff
        let bw: CGFloat = 7.5, bh: CGFloat = 5.0

        NSBezierPath(ovalIn: CGRect(x: bx - bw/2, y: by - bh/2,
                                    width: bw, height: bh)).fill()

        // ── Tail (triangle pointing left) ─────────────────────────────────
        let tailPath = NSBezierPath()
        let bodyLeft = bx - bw/2
        tailPath.move(to: CGPoint(x: bodyLeft, y: by - 1.0))
        tailPath.line(to: CGPoint(x: bodyLeft - 3.2, y: by + 0.6))
        tailPath.line(to: CGPoint(x: bodyLeft, y: by + 1.6))
        tailPath.close()
        tailPath.fill()

        // ── Head ──────────────────────────────────────────────────────────
        let hx = 11.0 + headDX
        let hy = 11.0 + bodyOff
        let hr: CGFloat = 2.5

        NSBezierPath(ovalIn: CGRect(x: hx - hr, y: hy - hr,
                                    width: hr * 2, height: hr * 2)).fill()

        // ── Crest (found state) ───────────────────────────────────────────
        if crest {
            let headTop = hy + hr
            let c = NSBezierPath()
            c.move(to: CGPoint(x: hx - 1.0, y: headTop))
            c.line(to: CGPoint(x: hx - 0.3, y: headTop + 2.0))
            c.line(to: CGPoint(x: hx + 0.8, y: headTop + 1.2))
            c.line(to: CGPoint(x: hx + 1.5, y: headTop + 3.0))
            c.line(to: CGPoint(x: hx + 2.3, y: headTop))
            c.close()
            c.fill()
        }

        // ── Beak ──────────────────────────────────────────────────────────
        let bkx = hx + hr, bky = hy + 0.2
        let beak = NSBezierPath()
        if beakOpen {
            // Upper mandible
            beak.move(to: CGPoint(x: bkx, y: bky + 0.6))
            beak.line(to: CGPoint(x: bkx + 2.3, y: bky + 1.1))
            beak.line(to: CGPoint(x: bkx + 2.3, y: bky + 0.2))
            beak.line(to: CGPoint(x: bkx, y: bky))
            beak.close()
            beak.fill()
            // Lower mandible
            let lower = NSBezierPath()
            lower.move(to: CGPoint(x: bkx, y: bky - 0.1))
            lower.line(to: CGPoint(x: bkx + 2.3, y: bky - 1.0))
            lower.line(to: CGPoint(x: bkx + 2.3, y: bky - 0.1))
            lower.line(to: CGPoint(x: bkx, y: bky))
            lower.close()
            lower.fill()
        } else {
            beak.move(to: CGPoint(x: bkx, y: bky + 0.7))
            beak.line(to: CGPoint(x: bkx + 2.3, y: bky))
            beak.line(to: CGPoint(x: bkx, y: bky - 0.7))
            beak.close()
            beak.fill()
        }

        // ── Eye (white dot on head) ───────────────────────────────────────
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: hx + 0.3, y: hy - 0.2,
                                    width: 1.4, height: 1.4)).fill()
        NSColor.black.setFill()

        // ── Legs (idle and ok) ────────────────────────────────────────────
        guard state == .idle || state == .ok else { return }

        let legTopY = by - bh / 2       // leg attaches to body bottom
        let legH: CGFloat = 2.2
        let legW: CGFloat = 0.8

        let strides: [[CGFloat]] = [[0, 0.6, 0, -0.6],   // left  [phase 0–3]
                                    [0, -0.6, 0, 0.6]]  // right [phase 0–3]
        let lOff = strides[0][legPhase % 4]
        let rOff = strides[1][legPhase % 4]

        let lx = bx - 1.5 + lOff
        let rx = bx + 0.7 + rOff

        NSBezierPath(rect: CGRect(x: lx, y: legTopY - legH,
                                  width: legW, height: legH)).fill()
        NSBezierPath(rect: CGRect(x: rx, y: legTopY - legH,
                                  width: legW, height: legH)).fill()
    }
}
