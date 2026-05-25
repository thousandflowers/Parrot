import AppKit

// MARK: - State

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
            walkX = facingLeft ? max(0, trackWidth - birdWidth) : 0
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
    private let birdWidth: CGFloat = 22

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
            statusItem?.length = trackWidth >= 60 ? trackWidth : birdWidth
        default:
            statusItem?.length = birdWidth
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
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        statePhase += dt
        if state == .walking { advanceWalk(dt: dt) }
        let p = buildParams()
        parrotView?.params = p
        parrotView?.setNeedsDisplay(parrotView?.bounds ?? .zero)
    }

    // MARK: - Walk

    private func advanceWalk(dt: Double) {
        guard trackWidth >= 60 else { return }
        let speed: CGFloat = 38
        walkX += (facingLeft ? -1 : 1) * speed * CGFloat(dt)
        if !facingLeft && walkX + birdWidth >= trackWidth {
            walkX = trackWidth - birdWidth; facingLeft = true
        } else if facingLeft && walkX <= 0 {
            walkX = 0; facingLeft = false
        }
    }

    // MARK: - Params

    private func buildParams() -> ParrotView.Params {
        var p = ParrotView.Params()
        let t = statePhase
        p.walkX = walkX
        p.facingLeft = facingLeft
        p.isWide = state == .walking && trackWidth >= 60
        p.canvasWidth = p.isWide ? trackWidth : birdWidth

        switch state {
        case .idle:
            p.bodyScaleY = 1 + 0.03 * CGFloat(sin(t * .pi))
            p.footLift = sin(t * .pi / 2) > 0 ? 0 : 1

        case .alert:
            let ease = CGFloat(min(1, t / 0.2))
            p.bodyScaleY = 1 + 0.10 * ease
            p.bodyScaleX = 1 - 0.08 * ease

        case .walking:
            let freq = 4.0 * Double.pi
            p.bodySway = 3 * CGFloat(sin(t * freq))
            p.headOffsetX = 1.5 * CGFloat(sin(t * freq + .pi * 0.5))
            p.legPhase = CGFloat(t.truncatingRemainder(dividingBy: 0.5) / 0.5)
            if trackWidth < 60 {
                p.bodyOffsetY = 2.5 * abs(CGFloat(sin(t * 3 * .pi)))
            }

        case .excited:
            let freq = 6.0 * Double.pi
            p.bodyScaleX = 1.08
            p.bodyScaleY = 1.08
            p.wingAngle = 15 * CGFloat(sin(t * freq)) * .pi / 180
            p.headOffsetY = 4 * CGFloat(sin(t * freq))
            p.beakOpen = max(0, CGFloat(sin(t * freq)))

        case .grooming:
            let freq = 1.5 * Double.pi
            p.headRotation = 20 * CGFloat(sin(t * freq)) * .pi / 180
            p.wingRaise = max(0, CGFloat(sin(t * freq)))

        case .approving:
            p.headOffsetY = 5 * CGFloat(sin(t * 6.67 * .pi))

        case .puffed:
            let puff: CGFloat = t < 0.3
                ? CGFloat(t / 0.3)
                : CGFloat(max(0, 1 - (t - 0.3) / 1.5))
            p.bodyScaleX = 1 + 0.15 * puff
            p.bodyScaleY = 1 + 0.12 * puff

        case .sleeping:
            p.bodyScaleY = 1 + 0.04 * CGFloat(sin(t * .pi * 0.6))
            p.headRotation = -.pi / 5
            p.headOffsetX = -2.0
            p.headOffsetY = -1.5
            p.sleeping = true
            p.sleepPhase = t
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
        var bodyScaleX: CGFloat = 1
        var bodyScaleY: CGFloat = 1
        var bodyOffsetY: CGFloat = 0
        var bodySway: CGFloat = 0
        var headOffsetX: CGFloat = 0
        var headOffsetY: CGFloat = 0
        var headRotation: CGFloat = 0
        var wingAngle: CGFloat = 0
        var wingRaise: CGFloat = 0
        var legPhase: CGFloat = 0
        var footLift: Int = 0
        var beakOpen: CGFloat = 0
        var walkX: CGFloat = 0
        var facingLeft: Bool = false
        var isWide: Bool = false
        var canvasWidth: CGFloat = 22
        var sleeping: Bool = false
        var sleepPhase: Double = 0
    }

    var params = Params()

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let isHighlighted = (superview as? NSButton)?.isHighlighted ?? false
        let ink: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        ink.setFill()
        ink.setStroke()

        ctx.saveGState()
        if params.isWide {
            ctx.translateBy(x: params.walkX, y: 0)
            if params.facingLeft {
                ctx.translateBy(x: 11, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -11, y: 0)
            }
        }
        drawParrot(ctx: ctx, ink: ink)
        ctx.restoreGState()

        if params.sleeping {
            drawZs(ctx: ctx, ink: ink)
        }
    }

    // MARK: - Drawing — canvas 22×22, y=0 at bottom (CG standard)

    private func drawParrot(ctx: CGContext, ink: NSColor) {
        let p = params
        let bx: CGFloat = 10
        let by: CGFloat = 10 + p.bodyOffsetY
        let bw = 9 * p.bodyScaleX
        let bh = 10 * p.bodyScaleY
        let sw = p.bodySway

        // ── Tail (two long curved feathers below body) ────────
        let tailRoot = CGPoint(x: bx - bw / 2 + sw, y: by - bh / 2)

        let tf1 = NSBezierPath()
        tf1.move(to: tailRoot)
        tf1.curve(to: CGPoint(x: tailRoot.x - 5, y: tailRoot.y - 6),
                  controlPoint1: CGPoint(x: tailRoot.x - 1, y: tailRoot.y - 2),
                  controlPoint2: CGPoint(x: tailRoot.x - 4, y: tailRoot.y - 3))
        tf1.line(to: CGPoint(x: tailRoot.x - 3.2, y: tailRoot.y - 6.5))
        tf1.curve(to: CGPoint(x: tailRoot.x, y: tailRoot.y),
                  controlPoint1: CGPoint(x: tailRoot.x - 2, y: tailRoot.y - 3),
                  controlPoint2: CGPoint(x: tailRoot.x - 0.5, y: tailRoot.y - 0.5))
        tf1.close()
        tf1.fill()

        let tf2 = NSBezierPath()
        tf2.move(to: CGPoint(x: tailRoot.x + 0.5, y: tailRoot.y + 0.8))
        tf2.curve(to: CGPoint(x: tailRoot.x - 2.5, y: tailRoot.y - 6.5),
                  controlPoint1: CGPoint(x: tailRoot.x + 0.5, y: tailRoot.y - 2),
                  controlPoint2: CGPoint(x: tailRoot.x - 2, y: tailRoot.y - 4))
        tf2.line(to: CGPoint(x: tailRoot.x - 0.8, y: tailRoot.y - 6.5))
        tf2.curve(to: CGPoint(x: tailRoot.x + 1.2, y: tailRoot.y + 0.8),
                  controlPoint1: CGPoint(x: tailRoot.x - 0.2, y: tailRoot.y - 2),
                  controlPoint2: CGPoint(x: tailRoot.x + 1, y: tailRoot.y - 0.2))
        tf2.close()
        tf2.fill()

        // ── Legs + feet ────────────────────────────────────────
        let legTopY = by - bh / 2
        let legH: CGFloat = 3.2
        let legW: CGFloat = 0.9
        let lx = bx - 1.5 + sw
        let rx = bx + 1.0 + sw

        let lLift: CGFloat = p.legPhase > 0.5 ? (p.legPhase - 0.5) * 2 * 1.8 : (p.footLift == 0 ? 1.2 : 0)
        let rLift: CGFloat = p.legPhase <= 0.5 ? p.legPhase * 2 * 1.8 : (p.footLift == 1 ? 1.2 : 0)

        NSBezierPath(rect: CGRect(x: lx, y: legTopY - legH + lLift, width: legW, height: legH - lLift)).fill()
        NSBezierPath(rect: CGRect(x: rx, y: legTopY - legH + rLift, width: legW, height: legH - rLift)).fill()

        if lLift < legH {
            let fy = legTopY - legH + lLift - 0.6
            NSBezierPath(rect: CGRect(x: lx - 1.2, y: fy, width: legW + 2.8, height: 0.8)).fill()
        }
        if rLift < legH {
            let fy = legTopY - legH + rLift - 0.6
            NSBezierPath(rect: CGRect(x: rx - 0.8, y: fy, width: legW + 2.8, height: 0.8)).fill()
        }

        // ── Body ──────────────────────────────────────────────
        NSBezierPath(ovalIn: CGRect(x: bx - bw/2 + sw, y: by - bh/2,
                                    width: bw, height: bh)).fill()

        // ── Wing detail / spread ───────────────────────────────
        if p.wingAngle != 0 {
            ctx.saveGState()
            ctx.translateBy(x: bx - bw/2 + sw, y: by)
            ctx.rotate(by: -p.wingAngle)
            let wl = NSBezierPath()
            wl.move(to: .zero)
            wl.line(to: CGPoint(x: -4.5, y: 3.5))
            wl.line(to: CGPoint(x: -2.5, y: 0))
            wl.close(); wl.fill()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: bx + bw/2 + sw, y: by)
            ctx.rotate(by: p.wingAngle)
            let wr = NSBezierPath()
            wr.move(to: .zero)
            wr.line(to: CGPoint(x: 4.5, y: 3.5))
            wr.line(to: CGPoint(x: 2.5, y: 0))
            wr.close(); wr.fill()
            ctx.restoreGState()
        } else if p.wingRaise > 0 {
            ctx.saveGState()
            ctx.translateBy(x: bx + bw/2 + sw, y: by + bh * 0.3)
            ctx.rotate(by: .pi / 5 * p.wingRaise)
            let wg = NSBezierPath()
            wg.move(to: .zero)
            wg.line(to: CGPoint(x: 4.0 * p.wingRaise, y: 2.5 * p.wingRaise))
            wg.line(to: CGPoint(x: 2.5, y: 0))
            wg.close(); wg.fill()
            ctx.restoreGState()
        } else {
            // Resting feather bar (white stripe on body)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: bx - 0.3 + sw, y: by + 0.5,
                                        width: 3.5, height: 1.2)).fill()
            ink.setFill()
        }

        // ── Head ──────────────────────────────────────────────
        let hx = 13.0 + p.headOffsetX + sw * 0.25
        let hy = 17.0 + p.headOffsetY + p.bodyOffsetY
        let hr: CGFloat = 3.5

        ctx.saveGState()
        ctx.translateBy(x: hx, y: hy)
        ctx.rotate(by: p.headRotation)
        NSBezierPath(ovalIn: CGRect(x: -hr, y: -hr, width: hr * 2, height: hr * 2)).fill()
        ctx.restoreGState()

        // ── Beak (curved, hooked downward) ────────────────────
        let bkx = hx + hr - 0.2
        let bky = hy + p.headRotation * 1.5

        if p.beakOpen > 0 {
            let upper = NSBezierPath()
            upper.move(to: CGPoint(x: bkx, y: bky + 0.4))
            upper.curve(to: CGPoint(x: bkx + 3.2, y: bky - 0.3),
                        controlPoint1: CGPoint(x: bkx + 1.2, y: bky + 1.2),
                        controlPoint2: CGPoint(x: bkx + 2.8, y: bky + 0.4))
            upper.line(to: CGPoint(x: bkx + 3.2, y: bky - 0.8 + p.beakOpen * 0.6))
            upper.line(to: CGPoint(x: bkx, y: bky - 0.1))
            upper.close(); upper.fill()

            let lower = NSBezierPath()
            lower.move(to: CGPoint(x: bkx, y: bky - 0.1))
            lower.curve(to: CGPoint(x: bkx + 2.6, y: bky - 2.2 - p.beakOpen * 0.8),
                        controlPoint1: CGPoint(x: bkx + 0.8, y: bky - 0.3),
                        controlPoint2: CGPoint(x: bkx + 2.2, y: bky - 1.4))
            lower.line(to: CGPoint(x: bkx + 3.2, y: bky - 0.8 + p.beakOpen * 0.6))
            lower.line(to: CGPoint(x: bkx, y: bky + 0.4))
            lower.close(); lower.fill()
        } else {
            let beak = NSBezierPath()
            beak.move(to: CGPoint(x: bkx, y: bky + 0.4))
            beak.curve(to: CGPoint(x: bkx + 3.5, y: bky - 1.2),
                       controlPoint1: CGPoint(x: bkx + 1.8, y: bky + 1.0),
                       controlPoint2: CGPoint(x: bkx + 3.5, y: bky + 0.2))
            beak.curve(to: CGPoint(x: bkx + 1.2, y: bky - 2.5),
                       controlPoint1: CGPoint(x: bkx + 3.5, y: bky - 2.2),
                       controlPoint2: CGPoint(x: bkx + 2.3, y: bky - 2.5))
            beak.line(to: CGPoint(x: bkx, y: bky - 0.4))
            beak.close(); beak.fill()
        }

        // ── Eye ───────────────────────────────────────────────
        if p.sleeping {
            NSColor.white.setStroke()
            let el = NSBezierPath()
            el.move(to: CGPoint(x: hx + 0.3, y: hy + 0.4))
            el.line(to: CGPoint(x: hx + 2.0, y: hy + 0.4))
            el.lineWidth = 0.9
            el.stroke()
            ink.setStroke()
        } else {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: hx + 0.5, y: hy + 0.1, width: 1.8, height: 1.8)).fill()
            ink.setFill()
        }
    }

    // MARK: - Sleeping Z's

    private func drawZs(ctx: CGContext, ink: NSColor) {
        let t = params.sleepPhase
        for i in 0 ..< 2 {
            let phase = t + Double(i) * 0.7
            let alpha = CGFloat(max(0, sin(phase * .pi * 0.8)))
            guard alpha > 0.05 else { continue }
            let yDrift = CGFloat(phase.truncatingRemainder(dividingBy: 1.25) / 1.25) * 4
            let x: CGFloat = 18 + CGFloat(i) * 1.5
            let y: CGFloat = 21 + yDrift + CGFloat(i) * 1.5
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 3.5 - CGFloat(i) * 0.5, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(alpha * 0.75)
            ]
            NSAttributedString(string: "z", attributes: attrs).draw(at: CGPoint(x: x, y: y))
        }
    }
}
