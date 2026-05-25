import AppKit

// MARK: - State controller

@MainActor
final class MenuBarParrot {
    static let shared = MenuBarParrot()
    private init() {}

    enum ParrotState: Equatable {
        case idle, alert, walking, excited, grooming, approving, puffed, sleeping
    }

    // MARK: - Public API

    private(set) var state: ParrotState = .idle

    func attach(to button: NSStatusBarButton, statusItem: NSStatusItem) {
        self.button = button
        self.statusItem = statusItem
        embedView(in: button)
        startAnimating()
        measureTrackWidth()
    }

    func setState(_ newState: ParrotState) {
        guard state != newState else { return }
        state = newState
        statePhase = 0
        autoTimer?.invalidate()
        autoTimer = nil
        applyLength()
        switch newState {
        case .walking:
            measureTrackWidth()
            walkX = facingLeft ? max(0, trackWidth - birdSlot) : 0
        case .idle:
            measureTrackWidth()
        default: break
        }
        scheduleAutoReset()
    }

    func stopAnimating() {
        animTimer?.invalidate()
        animTimer = nil
    }

    // MARK: - Private state

    private weak var button: NSStatusBarButton?
    private weak var statusItem: NSStatusItem?
    private var parrotView: ParrotView?
    private var animTimer: Timer?
    private var autoTimer: Timer?
    private var lastTick: Date = .now

    private var statePhase: Double = 0
    private var walkX: CGFloat = 0
    private var facingLeft: Bool = false
    private var trackWidth: CGFloat = 80
    private let birdSlot: CGFloat = 22

    // MARK: - Setup

    private func embedView(in button: NSStatusBarButton) {
        let v = ParrotView(frame: button.bounds)
        v.autoresizingMask = [.width, .height]
        button.addSubview(v)
        parrotView = v
    }

    private func applyLength() {
        switch state {
        case .walking:
            statusItem?.length = trackWidth >= 60 ? trackWidth : birdSlot
        default:
            statusItem?.length = birdSlot
        }
    }

    private func measureTrackWidth() {
        guard let si = statusItem else { return }
        si.length = NSStatusItem.variableLength
        let t = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.trackWidth = self.computeFreeWidth()
                self.applyLength()
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    private func computeFreeWidth() -> CGFloat {
        guard let button, let win = button.window else { return 80 }
        return max(44, min(800, win.frame.origin.x - 220))
    }

    // MARK: - Animation timer (60 fps)

    private func startAnimating() {
        animTimer?.invalidate()
        lastTick = .now
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func tick() {
        let now = Date.now
        // Cap dt: prevents huge jump after app returns from background
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        statePhase += dt
        if state == .walking { advanceWalk(dt: dt) }
        parrotView?.params = buildParams()
        parrotView?.needsDisplay = true
    }

    // MARK: - Walk

    private func advanceWalk(dt: Double) {
        guard trackWidth >= 60 else { return }
        let speed: CGFloat = 38   // pts/sec in screen space
        walkX += (facingLeft ? -1 : 1) * speed * CGFloat(dt)
        if !facingLeft && walkX + birdSlot >= trackWidth {
            walkX = trackWidth - birdSlot; facingLeft = true
        } else if facingLeft && walkX <= 0 {
            walkX = 0; facingLeft = false
        }
    }

    // MARK: - Params (values in design units, 0–18 range)

    private func buildParams() -> ParrotView.Params {
        var p = ParrotView.Params()
        let t = statePhase

        p.walkX       = walkX
        p.facingLeft  = facingLeft
        p.isWide      = state == .walking && trackWidth >= 60
        p.canvasWidth = p.isWide ? trackWidth : birdSlot

        switch state {

        case .idle:
            // Slow breathing (0.5 Hz) + alternating foot lift
            p.bodyScaleY = 1 + 0.025 * CGFloat(sin(t * .pi))
            p.footLift   = sin(t * .pi / 2) > 0 ? 0 : 1

        case .alert:
            // Quick stretch upward (0.25 s ease-in)
            let ease    = CGFloat(min(1, t / 0.25))
            p.bodyScaleY = 1 + 0.10 * ease
            p.bodyScaleX = 1 - 0.07 * ease

        case .walking:
            // Lateral body sway + alternating legs + head bob
            let freq     = 3.5 * Double.pi   // ~1.75 Hz
            p.bodySway   = 1.0 * CGFloat(sin(t * freq))
            p.headOffsetX = 0.6 * CGFloat(sin(t * freq + .pi * 0.5))
            // legCycle: continuous sawtooth 0→1 every 0.5 s
            p.legCycle   = CGFloat(t.truncatingRemainder(dividingBy: 0.5) / 0.5)
            if trackWidth < 60 {
                // No free space: hop in place
                p.bodyOffsetY = 1.2 * abs(CGFloat(sin(t * 3 * .pi)))
            }

        case .excited:
            // Fast head bob (2.5 Hz) + wings spread + open beak
            let freq     = 5.0 * Double.pi
            p.bodyScaleX = 1.08
            p.bodyScaleY = 1.08
            p.wingAngle  = 14 * CGFloat(sin(t * freq)) * .pi / 180
            p.headOffsetY = 2.0 * CGFloat(sin(t * freq))
            // Offset beak phase so it opens on downstroke (looks natural)
            p.beakOpen   = max(0, CGFloat(sin(t * freq + .pi * 0.5)))

        case .grooming:
            // Head tilts side to side, right wing raises
            let freq       = 1.2 * Double.pi
            p.headRotation = 16 * CGFloat(sin(t * freq)) * .pi / 180
            p.wingRaise    = max(0, CGFloat(sin(t * freq)))

        case .approving:
            // 3 gentle head bobs then settle
            let decay      = CGFloat(max(0, 1 - t / 1.2))   // fade over 1.2 s
            p.headOffsetY  = 2.0 * CGFloat(sin(t * 6 * .pi)) * decay

        case .puffed:
            // Fast inflate (0.3 s), slow deflate (1.5 s)
            let puff: CGFloat = t < 0.3
                ? CGFloat(t / 0.3)
                : CGFloat(max(0, 1 - (t - 0.3) / 1.5))
            p.bodyScaleX = 1 + 0.16 * puff
            p.bodyScaleY = 1 + 0.13 * puff

        case .sleeping:
            // Slow breathing (0.25 Hz) + head tucked + right wing covers head
            p.bodyScaleY   = 1 + 0.03 * CGFloat(sin(t * .pi * 0.5))
            p.headRotation = -.pi / 6      // 30° droop forward
            p.headOffsetX  = -1.5
            p.headOffsetY  = -1.0
            p.wingRaise    = 0.75          // wing raised over tucked head
            p.sleeping     = true
            p.sleepPhase   = t
        }

        return p
    }

    // MARK: - Auto-reset

    private func scheduleAutoReset() {
        let delay: TimeInterval
        switch state {
        case .alert:     delay = 3.0
        case .excited:   delay = 5.0
        case .grooming:  delay = 3.5
        case .approving: delay = 1.5
        case .puffed:    delay = 2.0
        default: return
        }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.setState(.idle) }
        }
        RunLoop.main.add(t, forMode: .common)
        autoTimer = t
    }
}

// MARK: - ParrotView

final class ParrotView: NSView {

    struct Params {
        var bodyScaleX:  CGFloat = 1
        var bodyScaleY:  CGFloat = 1
        var bodyOffsetY: CGFloat = 0
        var bodySway:    CGFloat = 0     // design units, lateral
        var headOffsetX: CGFloat = 0
        var headOffsetY: CGFloat = 0
        var headRotation: CGFloat = 0    // radians
        var wingAngle:   CGFloat = 0     // radians (excited spread)
        var wingRaise:   CGFloat = 0     // 0–1 (grooming/sleeping)
        var legCycle:    CGFloat = 0     // 0–1 sawtooth → alternating sin legs
        var footLift:    Int     = 0     // 0=left up, 1=right up (idle)
        var beakOpen:    CGFloat = 0     // 0=closed, 1=fully open
        var walkX:       CGFloat = 0
        var facingLeft:  Bool    = false
        var isWide:      Bool    = false
        var canvasWidth: CGFloat = 22
        var sleeping:    Bool    = false
        var sleepPhase:  Double  = 0
    }

    var params = Params()

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    // All drawing done in a 18×18 design space, then scaled to view bounds.
    // Coordinate origin: bottom-left, y increases upward (CG standard).
    //
    // Layout (design units):
    //   Feet     y ≈ 0–0.7
    //   Legs     y ≈ 0.7–3.0   (x 6.5 and 8.8)
    //   Tail     fans LEFT from body-left (4, 7.5), stays y ≥ 3.0
    //   Body     oval cx=8, cy=7.5, w=8, h=9   (y: 3–12)
    //   Head     circle cx=12, cy=14, r=3.2     (y: 10.8–17.2)
    //   Beak     drawn IN head-local space → rotates correctly with head
    //   Eye      drawn IN head-local space

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let isHighlighted = (superview as? NSButton)?.isHighlighted ?? false
        let ink: NSColor  = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        ink.setFill()
        ink.setStroke()

        // Walking: translate + optional flip in SCREEN space (before scale)
        ctx.saveGState()
        if params.isWide {
            ctx.translateBy(x: params.walkX, y: 0)
            if params.facingLeft {
                // Flip around center of one bird slot (≈ view height wide)
                let c = bounds.height / 2
                ctx.translateBy(x: c, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -c, y: 0)
            }
        }

        // Scale 18-unit design space to view height
        let s = bounds.height / 18.0
        ctx.scaleBy(x: s, y: s)

        drawBird(ctx: ctx, ink: ink)
        ctx.restoreGState()

        if params.sleeping {
            drawZs(ctx: ctx, ink: ink)
        }
    }

    // MARK: - Bird drawing (all coords in design units, y=0 bottom)

    private func drawBird(ctx: CGContext, ink: NSColor) {
        let p = params

        // Contrast colour for details (feather bar, eye, closed eye line)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let detail: NSColor = isDark ? NSColor(white: 0.08, alpha: 1) : .white

        // Body geometry
        let bx: CGFloat   = 8.0
        let by: CGFloat   = 7.5 + p.bodyOffsetY
        let bw            = 8.0 * p.bodyScaleX
        let bh            = 9.0 * p.bodyScaleY
        let sw            = p.bodySway
        let bodyLeft      = bx - bw / 2 + sw
        let bodyRight     = bx + bw / 2 + sw
        let bodyBot       = by - bh / 2
        let bodyTop       = by + bh / 2

        // ── Tail (two fans extending LEFT from body, y always ≥ 3) ──────
        // Feather 1: lower fan
        let tf1 = NSBezierPath()
        tf1.move(to:   NSPoint(x: bodyLeft,       y: bodyBot + 1.5))
        tf1.curve(to:  NSPoint(x: 0.5,            y: 4.2),
                  controlPoint1: NSPoint(x: bodyLeft - 1.5, y: bodyBot + 0.5),
                  controlPoint2: NSPoint(x: 1.5,            y: 4.8))
        tf1.line(to:   NSPoint(x: 0.5,            y: 3.2))
        tf1.curve(to:  NSPoint(x: bodyLeft,       y: bodyBot),
                  controlPoint1: NSPoint(x: 1.5,            y: 3.4),
                  controlPoint2: NSPoint(x: bodyLeft - 1.0, y: bodyBot - 0.2))
        tf1.close(); tf1.fill()

        // Feather 2: upper fan
        let tf2 = NSBezierPath()
        tf2.move(to:   NSPoint(x: bodyLeft,       y: bodyBot + 2.5))
        tf2.curve(to:  NSPoint(x: 0.4,            y: 5.8),
                  controlPoint1: NSPoint(x: bodyLeft - 1.0, y: bodyBot + 2.0),
                  controlPoint2: NSPoint(x: 1.0,            y: 6.2))
        tf2.line(to:   NSPoint(x: 0.5,            y: 5.0))
        tf2.curve(to:  NSPoint(x: bodyLeft,       y: bodyBot + 1.5),
                  controlPoint1: NSPoint(x: 1.0,            y: 5.0),
                  controlPoint2: NSPoint(x: bodyLeft - 0.8, y: bodyBot + 1.2))
        tf2.close(); tf2.fill()

        // ── Legs + feet ──────────────────────────────────────────────────
        let legTopY: CGFloat = bodyBot
        let legH: CGFloat    = 2.8
        let legW: CGFloat    = 0.85
        let lx = bx - 1.5 + sw
        let rx = bx + 0.8 + sw

        // Smooth sinusoidal alternating leg lift (no step discontinuity)
        let lLift: CGFloat
        let rLift: CGFloat
        if p.legCycle > 0 {
            let cyc = Double(p.legCycle)
            lLift = 1.3 * max(0, CGFloat(sin(cyc * 2 * .pi)))
            rLift = 1.3 * max(0, CGFloat(sin(cyc * 2 * .pi + .pi)))
        } else {
            lLift = p.footLift == 0 ? 0.9 : 0
            rLift = p.footLift == 1 ? 0.9 : 0
        }

        let lLegH = max(0, legH - lLift)
        let rLegH = max(0, legH - rLift)
        if lLegH > 0.1 { NSBezierPath(rect: CGRect(x: lx, y: legTopY - lLegH, width: legW, height: lLegH)).fill() }
        if rLegH > 0.1 { NSBezierPath(rect: CGRect(x: rx, y: legTopY - rLegH, width: legW, height: rLegH)).fill() }

        // Feet appear only when leg is near ground
        let footH: CGFloat = 0.7
        let footW: CGFloat = 2.8
        let footThreshold  = legH - 0.3
        if lLift < footThreshold {
            let fy = max(0, legTopY - legH - footH * 0.3)
            NSBezierPath(rect: CGRect(x: lx - 1.1, y: fy, width: legW + footW, height: footH)).fill()
        }
        if rLift < footThreshold {
            let fy = max(0, legTopY - legH - footH * 0.3)
            NSBezierPath(rect: CGRect(x: rx - 0.8, y: fy, width: legW + footW, height: footH)).fill()
        }

        // ── Body ─────────────────────────────────────────────────────────
        NSBezierPath(ovalIn: CGRect(x: bodyLeft, y: bodyBot, width: bw, height: bh)).fill()

        // ── Wings ─────────────────────────────────────────────────────────
        let hasSpread = abs(p.wingAngle) > 0.01
        let hasRaise  = p.wingRaise > 0.05

        if hasSpread {
            // Excited: wings spread from body sides
            ctx.saveGState()
            ctx.translateBy(x: bodyLeft, y: by)
            ctx.rotate(by: -p.wingAngle)
            let wl = NSBezierPath()
            wl.move(to: .zero)
            wl.line(to: NSPoint(x: -3.5, y: 3.0))
            wl.line(to: NSPoint(x: -2.0, y: 0))
            wl.close(); wl.fill()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: bodyRight, y: by)
            ctx.rotate(by: p.wingAngle)
            let wr = NSBezierPath()
            wr.move(to: .zero)
            wr.line(to: NSPoint(x: 3.5, y: 3.0))
            wr.line(to: NSPoint(x: 2.0, y: 0))
            wr.close(); wr.fill()
            ctx.restoreGState()

        } else if hasRaise {
            // Grooming / sleeping: right wing lifts toward head
            ctx.saveGState()
            ctx.translateBy(x: bodyRight, y: by + bh * 0.28)
            ctx.rotate(by: .pi / 4 * p.wingRaise)
            let wg = NSBezierPath()
            wg.move(to: .zero)
            wg.line(to: NSPoint(x: 3.2 * p.wingRaise, y: 2.2 * p.wingRaise))
            wg.line(to: NSPoint(x: 2.5, y: 0))
            wg.close(); wg.fill()
            ctx.restoreGState()

        } else {
            // Resting: white feather detail bar on body
            detail.setFill()
            NSBezierPath(ovalIn: CGRect(x: bx - 0.3 + sw, y: by + 0.8,
                                        width: 3.2, height: 1.0)).fill()
            ink.setFill()
        }

        // ── Head + Beak + Eye (all in head-local space) ──────────────────
        // Drawing inside one saveGState/restoreGState means beak and eye
        // automatically follow head rotation — no separate trig needed.
        let hx: CGFloat = 12.0 + p.headOffsetX + sw * 0.4
        let hy: CGFloat = 14.0 + p.headOffsetY + p.bodyOffsetY
        let hr: CGFloat = 3.2

        ctx.saveGState()
        ctx.translateBy(x: hx, y: hy)
        ctx.rotate(by: p.headRotation)

        // Head circle
        NSBezierPath(ovalIn: CGRect(x: -hr, y: -hr, width: hr * 2, height: hr * 2)).fill()

        // Beak (skipped when sleeping — head tucked under wing)
        if !p.sleeping {
            let bkx: CGFloat = hr - 0.2   // right edge of head
            let bky: CGFloat = 0.0        // at head midline

            if p.beakOpen > 0.1 {
                // Open beak: upper + lower mandible
                let upper = NSBezierPath()
                upper.move(to: NSPoint(x: bkx,       y: bky + 0.4))
                upper.curve(to: NSPoint(x: bkx + 2.4, y: bky - 0.1),
                            controlPoint1: NSPoint(x: bkx + 0.9,  y: bky + 1.0),
                            controlPoint2: NSPoint(x: bkx + 2.2,  y: bky + 0.5))
                upper.line(to: NSPoint(x: bkx + 2.4, y: bky - 0.1 - p.beakOpen * 0.9))
                upper.line(to: NSPoint(x: bkx,       y: bky - 0.1))
                upper.close(); upper.fill()

                let lower = NSBezierPath()
                lower.move(to: NSPoint(x: bkx,       y: bky - 0.1))
                lower.curve(to: NSPoint(x: bkx + 2.0, y: bky - 1.7 - p.beakOpen * 1.0),
                            controlPoint1: NSPoint(x: bkx + 0.7,  y: bky - 0.4),
                            controlPoint2: NSPoint(x: bkx + 1.8,  y: bky - 1.2))
                lower.line(to: NSPoint(x: bkx + 2.4, y: bky - 0.1 - p.beakOpen * 0.9))
                lower.line(to: NSPoint(x: bkx,       y: bky + 0.4))
                lower.close(); lower.fill()
            } else {
                // Closed hooked beak
                let beak = NSBezierPath()
                beak.move(to: NSPoint(x: bkx,        y: bky + 0.4))
                beak.curve(to: NSPoint(x: bkx + 2.6,  y: bky - 0.8),
                           controlPoint1: NSPoint(x: bkx + 1.3,  y: bky + 0.9),
                           controlPoint2: NSPoint(x: bkx + 2.6,  y: bky + 0.2))
                beak.curve(to: NSPoint(x: bkx + 0.9,  y: bky - 1.9),
                           controlPoint1: NSPoint(x: bkx + 2.6,  y: bky - 1.7),
                           controlPoint2: NSPoint(x: bkx + 1.9,  y: bky - 1.9))
                beak.line(to: NSPoint(x: bkx,        y: bky - 0.3))
                beak.close(); beak.fill()
            }
        }

        // Eye (in head-local space, right-forward quadrant)
        if p.sleeping {
            // Closed: thin contrast line
            detail.setStroke()
            let el = NSBezierPath()
            el.move(to: NSPoint(x: 0.4, y: 0.5))
            el.line(to: NSPoint(x: 2.0, y: 0.5))
            el.lineWidth = 0.8
            el.stroke()
            ink.setStroke()
        } else {
            detail.setFill()
            NSBezierPath(ovalIn: CGRect(x: 0.5, y: 0.1, width: 1.6, height: 1.6)).fill()
            ink.setFill()
        }

        ctx.restoreGState()
    }

    // MARK: - Sleeping Z's (drawn in screen space, outside the design scale)

    private func drawZs(ctx: CGContext, ink: NSColor) {
        let t  = params.sleepPhase
        let h  = bounds.height
        for i in 0 ..< 2 {
            let phase = t + Double(i) * 0.8
            let alpha = CGFloat(max(0, sin(phase * .pi * 0.7)))
            guard alpha > 0.05 else { continue }
            let drift  = CGFloat(phase.truncatingRemainder(dividingBy: 1.4) / 1.4) * h * 0.18
            let xPos   = h * 0.83 + CGFloat(i) * h * 0.14
            let yPos   = h * 0.92 + drift + CGFloat(i) * h * 0.12
            let size   = h * (0.20 - CGFloat(i) * 0.04)
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(alpha * 0.7)
            ]
            NSAttributedString(string: "z", attributes: attrs).draw(at: CGPoint(x: xPos, y: yPos))
        }
    }
}
