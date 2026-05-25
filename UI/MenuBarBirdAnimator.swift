import AppKit

/// Drives a frame-animated monochromatic bird silhouette in the menu bar status button.
///
/// States:
///   idle       — walking leg cycle, wing bar visible
///   analyzing  — smooth side-to-side head scan
///   found      — excited bounce, crest raised, beak open, wings fanned
///   ok         — gentle settle with small nod
///   error      — body slumps, head droops, eye closed
@MainActor
final class MenuBarBirdAnimator {
    static let shared = MenuBarBirdAnimator()
    private init() {}

    enum BirdState: Equatable { case idle, analyzing, found, ok, error }

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
        case .analyzing: return 10
        case .found:     return 12
        case .ok:        return 4
        case .error:     return 4
        }
    }

    private var frameCount: Int {
        switch state {
        case .idle:      return 8
        case .analyzing: return 8
        case .found:     return 8
        case .ok:        return 4
        case .error:     return 4
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
        case .error: delay = 4.0
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
    // Canvas: 18×18 pt, y=0 at bottom (NSImage flipped:false = AppKit standard, y↑).
    //
    // Layout (resting):
    //   Feet        y  2–4   (horizontal ticks at leg bottom)
    //   Legs        y  4–6.5
    //   Body        y  4–9   (oval, cx=8, cy=6.5, w=8, h=5.5)
    //   Wing bar    y  7.5   (white stripe on body = feather detail)
    //   Tail        extends left (two fanned triangles)
    //   Head        y  8.5–13.5 (circle, cx=11, cy=11, r=2.6)
    //   Beak        extends right from head
    //   Eye         white dot on head
    //   Crest       y  13.5+ (found state)

    private static func drawBird(state: BirdState, frame: Int) {
        var bodyOff: CGFloat = 0
        var headDX: CGFloat = 0
        var headDY: CGFloat = 0
        var crest = false
        var beakOpen = false
        var legPhase = 0
        var eyeClosed = false
        var wingsUp = false

        switch state {
        case .idle:
            let bobs: [CGFloat] = [0, 0.3, 0.5, 0.3, 0, -0.2, -0.3, -0.2]
            bodyOff = bobs[frame % 8]
            legPhase = frame % 4

        case .analyzing:
            // Smooth left-right head scan with slight elevation at extremes
            let sweep: [CGFloat] = [0, -0.5, -1.1, -1.3, -0.9, -0.3, 0.4, 0.7]
            headDX = sweep[frame % 8]
            headDY = abs(sweep[frame % 8]) * 0.18

        case .found:
            let jumps: [CGFloat] = [0, 1.0, 2.2, 2.8, 2.0, 1.0, 0.3, 0]
            bodyOff = jumps[frame % 8]
            crest = true
            beakOpen = frame % 3 != 0
            wingsUp = frame >= 2 && frame <= 5

        case .ok:
            let settles: [CGFloat] = [0.3, 0.1, 0.25, 0]
            bodyOff = settles[frame % 4]
            legPhase = 0

        case .error:
            // Body slumps down, head droops forward
            let droops: [CGFloat] = [-0.6, -1.0, -1.1, -0.9]
            bodyOff = droops[frame % 4]
            headDX = -1.8
            headDY = -1.6
            eyeClosed = true
        }

        NSColor.black.setFill()

        // ── Body ──────────────────────────────────────────────────────────
        let bx: CGFloat = 8.0
        let by = 6.5 + bodyOff
        let bw: CGFloat = 8.0, bh: CGFloat = 5.5

        NSBezierPath(ovalIn: CGRect(x: bx - bw/2, y: by - bh/2,
                                    width: bw, height: bh)).fill()

        // ── Wing bar (white stripe = visible feather detail) ───────────────
        if !wingsUp {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: bx - 1.0, y: by + 0.6,
                                        width: 3.8, height: 1.3)).fill()
            NSColor.black.setFill()
        }

        // ── Wings spread (found state, mid-jump frames) ────────────────────
        if wingsUp {
            let wl = NSBezierPath()
            wl.move(to: CGPoint(x: bx - 1.0, y: by + bh/2 - 0.3))
            wl.line(to: CGPoint(x: bx - 4.5, y: by + bh/2 + 2.5))
            wl.line(to: CGPoint(x: bx - 2.5, y: by + bh/2 - 0.3))
            wl.close()
            wl.fill()

            let wr = NSBezierPath()
            wr.move(to: CGPoint(x: bx + 2.0, y: by + bh/2 - 0.3))
            wr.line(to: CGPoint(x: bx + 5.0, y: by + bh/2 + 2.0))
            wr.line(to: CGPoint(x: bx + 3.5, y: by + bh/2 - 0.3))
            wr.close()
            wr.fill()
        }

        // ── Tail (two fanned feathers) ─────────────────────────────────────
        let bodyLeft = bx - bw/2
        let t1 = NSBezierPath()
        t1.move(to: CGPoint(x: bodyLeft + 0.2, y: by - 1.2))
        t1.line(to: CGPoint(x: bodyLeft - 3.5, y: by + 0.4))
        t1.line(to: CGPoint(x: bodyLeft, y: by + 1.3))
        t1.close()
        t1.fill()

        let t2 = NSBezierPath()
        t2.move(to: CGPoint(x: bodyLeft + 0.5, y: by + 0.6))
        t2.line(to: CGPoint(x: bodyLeft - 2.8, y: by + 2.8))
        t2.line(to: CGPoint(x: bodyLeft, y: by + 2.0))
        t2.close()
        t2.fill()

        // ── Head ──────────────────────────────────────────────────────────
        let hx = 11.0 + headDX
        let hy = 11.0 + bodyOff + headDY
        let hr: CGFloat = 2.6

        NSBezierPath(ovalIn: CGRect(x: hx - hr, y: hy - hr,
                                    width: hr * 2, height: hr * 2)).fill()

        // ── Crest (found state) ───────────────────────────────────────────
        if crest {
            let top = hy + hr
            let c = NSBezierPath()
            c.move(to: CGPoint(x: hx - 1.3, y: top))
            c.line(to: CGPoint(x: hx - 0.4, y: top + 2.6))
            c.line(to: CGPoint(x: hx + 0.6, y: top + 1.4))
            c.line(to: CGPoint(x: hx + 1.3, y: top + 3.5))
            c.line(to: CGPoint(x: hx + 2.5, y: top + 0.8))
            c.line(to: CGPoint(x: hx + 2.0, y: top))
            c.close()
            c.fill()
        }

        // ── Beak ──────────────────────────────────────────────────────────
        if state != .error {
            let bkx = hx + hr, bky = hy + 0.2
            let beak = NSBezierPath()
            if beakOpen {
                beak.move(to: CGPoint(x: bkx, y: bky + 0.7))
                beak.line(to: CGPoint(x: bkx + 2.5, y: bky + 1.2))
                beak.line(to: CGPoint(x: bkx + 2.5, y: bky + 0.3))
                beak.line(to: CGPoint(x: bkx, y: bky))
                beak.close()
                beak.fill()
                let lower = NSBezierPath()
                lower.move(to: CGPoint(x: bkx, y: bky - 0.1))
                lower.line(to: CGPoint(x: bkx + 2.5, y: bky - 1.1))
                lower.line(to: CGPoint(x: bkx + 2.5, y: bky - 0.2))
                lower.line(to: CGPoint(x: bkx, y: bky))
                lower.close()
                lower.fill()
            } else {
                beak.move(to: CGPoint(x: bkx, y: bky + 0.7))
                beak.line(to: CGPoint(x: bkx + 2.5, y: bky))
                beak.line(to: CGPoint(x: bkx, y: bky - 0.7))
                beak.close()
                beak.fill()
            }
        } else {
            // Error: beak points down, tucked
            let bkx = hx + hr - 0.5, bky = hy - 0.5
            let beak = NSBezierPath()
            beak.move(to: CGPoint(x: bkx, y: bky))
            beak.line(to: CGPoint(x: bkx + 1.8, y: bky - 1.8))
            beak.line(to: CGPoint(x: bkx - 0.3, y: bky - 0.8))
            beak.close()
            beak.fill()
        }

        // ── Eye ───────────────────────────────────────────────────────────
        if eyeClosed {
            // Thin white line = closed/sad eye
            let eyeLine = NSBezierPath()
            eyeLine.move(to: CGPoint(x: hx + 0.1, y: hy + 0.3))
            eyeLine.line(to: CGPoint(x: hx + 1.6, y: hy + 0.3))
            eyeLine.lineWidth = 0.8
            NSColor.white.setStroke()
            eyeLine.stroke()
        } else {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: hx + 0.2, y: hy - 0.2,
                                        width: 1.5, height: 1.5)).fill()
        }
        NSColor.black.setFill()

        // ── Legs + Feet ───────────────────────────────────────────────────
        guard state == .idle || state == .ok || state == .analyzing else { return }

        let legTopY = by - bh / 2
        let legH: CGFloat = 2.4
        let legW: CGFloat = 0.8

        let strides: [[CGFloat]] = [[0, 0.7, 0, -0.7],
                                    [0, -0.7, 0, 0.7]]
        let lOff = strides[0][legPhase % 4]
        let rOff = strides[1][legPhase % 4]
        let lx = bx - 1.5 + lOff
        let rx = bx + 0.7 + rOff

        // Legs
        NSBezierPath(rect: CGRect(x: lx, y: legTopY - legH, width: legW, height: legH)).fill()
        NSBezierPath(rect: CGRect(x: rx, y: legTopY - legH, width: legW, height: legH)).fill()

        // Feet (small horizontal ticks)
        NSBezierPath(rect: CGRect(x: lx - 0.6, y: legTopY - legH - 0.1,
                                   width: legW + 1.4, height: 0.7)).fill()
        NSBezierPath(rect: CGRect(x: rx - 0.4, y: legTopY - legH - 0.1,
                                   width: legW + 1.4, height: 0.7)).fill()
    }
}
