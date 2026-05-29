import AppKit

// MARK: - State controller

@MainActor
final class MenuBarParrot {
    static let shared = MenuBarParrot()
    private init() {}

    enum ParrotState: Equatable {
        case idle, alert, walking, excited, approving, puffed, sleeping
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
        prevParams  = parrotView?.params ?? ParrotView.Params()
        blendFactor = 0.0
        state       = newState
        statePhase  = 0
        autoTimer?.invalidate()
        autoTimer   = nil
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

    // Smooth state transition blend
    private var prevParams  = ParrotView.Params()
    private var blendFactor = 1.0
    private let blendDuration = 0.22

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
        let dt  = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if state != .idle { setState(.idle) }
            parrotView?.params = buildParams()
            parrotView?.needsDisplay = true
            return
        }
        statePhase  += dt
        blendFactor  = min(1.0, blendFactor + dt / blendDuration)
        if state == .walking { advanceWalk(dt: dt) }
        let cur    = buildParams()
        let merged = blendFactor >= 1.0 ? cur : ParrotView.Params.lerp(prevParams, cur, CGFloat(blendFactor))
        parrotView?.params = merged
        parrotView?.needsDisplay = true
    }

    // MARK: - Walk

    private func advanceWalk(dt: Double) {
        guard trackWidth >= 60 else { return }
        let speed: CGFloat = 36
        walkX += (facingLeft ? -1 : 1) * speed * CGFloat(dt)
        if !facingLeft && walkX + birdSlot >= trackWidth {
            walkX = trackWidth - birdSlot; facingLeft = true
        } else if facingLeft && walkX <= 0 {
            walkX = 0; facingLeft = false
        }
    }

    // MARK: - Params (design units 0–18)

    private func buildParams() -> ParrotView.Params {
        var p = ParrotView.Params()
        let t = statePhase

        p.walkX      = walkX
        p.facingLeft = facingLeft
        p.isWide     = state == .walking && trackWidth >= 60
        p.canvasWidth = p.isWide ? trackWidth : birdSlot

        switch state {

        case .idle:
            let breath    = t * 1.2 * .pi
            p.bodyScaleY  = 1 + 0.030 * CGFloat(sin(breath))
            p.bodyScaleX  = 1 - 0.012 * CGFloat(sin(breath))
            p.bodyOffsetY = 0.15 * CGFloat(sin(t * 0.8 * .pi))

        case .alert:
            let ease      = CGFloat(smoothstep(t / 0.3))
            p.bodyScaleY  = 1 + 0.12 * ease
            p.bodyScaleX  = 1 - 0.09 * ease
            p.bodyOffsetY = 1.5 * ease

        case .walking:
            let step = t * 4 * .pi
            p.bodySway    = 0.9 * CGFloat(sin(step))
            p.bodyOffsetY = 0.40 * abs(CGFloat(sin(step)))
            if trackWidth < 60 {
                p.bodySway    = 0
                p.bodyOffsetY = 1.6 * abs(CGFloat(sin(t * 3 * .pi)))
            }

        case .excited:
            let freq = 5.0 * Double.pi
            p.bodyScaleX  = 1.08
            p.bodyScaleY  = 1.08
            p.bodyOffsetY = 1.5 * CGFloat(sin(t * freq))
            p.beakOpen    = max(0, CGFloat(sin(t * freq + .pi * 0.5)))

        case .approving:
            let decay = CGFloat(max(0, 1 - t / 1.0))
            p.bodyOffsetY = 3.0 * CGFloat(sin(t * 5 * .pi)) * decay

        case .puffed:
            let raw: Double = t < 0.3 ? t / 0.3 : max(0, 1 - (t - 0.3) / 1.5)
            let puff  = CGFloat(raw)
            let tremor = 0.020 * CGFloat(sin(t * 18 * .pi)) * puff
            p.bodyScaleX = 1 + 0.18 * puff + tremor
            p.bodyScaleY = 1 + 0.15 * puff

        case .sleeping:
            p.bodyScaleY   = 1 + 0.025 * CGFloat(sin(t * .pi * 0.4))
            p.bodyOffsetX  = -0.3
            p.bodyOffsetY  = -1.5
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

// Cubic S-curve easing
private func smoothstep(_ x: Double) -> Double {
    let t = max(0, min(1, x))
    return t * t * (3 - 2 * t)
}

// MARK: - ParrotView

final class ParrotView: NSView {

    struct Params {
        var bodyScaleX:  CGFloat = 1
        var bodyScaleY:  CGFloat = 1
        var bodyOffsetX: CGFloat = 0
        var bodyOffsetY: CGFloat = 0
        var bodySway:    CGFloat = 0
        var beakOpen:    CGFloat = 0
        var walkX:       CGFloat = 0
        var facingLeft:  Bool    = false
        var isWide:      Bool    = false
        var canvasWidth: CGFloat = 22
        var sleeping:    Bool    = false
        var sleepPhase:  Double  = 0

        static func lerp(_ a: Params, _ b: Params, _ t: CGFloat) -> Params {
            let u = max(0, min(1, t))
            func f(_ av: CGFloat, _ bv: CGFloat) -> CGFloat { av + (bv - av) * u }
            var r          = b
            r.bodyScaleX   = f(a.bodyScaleX,   b.bodyScaleX)
            r.bodyScaleY   = f(a.bodyScaleY,   b.bodyScaleY)
            r.bodyOffsetX  = f(a.bodyOffsetX,  b.bodyOffsetX)
            r.bodyOffsetY  = f(a.bodyOffsetY,  b.bodyOffsetY)
            r.bodySway     = f(a.bodySway,     b.bodySway)
            r.beakOpen     = f(a.beakOpen,     b.beakOpen)
            return r
        }
    }

    var params = Params()

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    // Single unified silhouette path at 18×18 design space.
    // Ollama-style: monochrome, continuous outline, beak is the hero.

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let isHighlighted = (superview as? NSButton)?.isHighlighted ?? false
        let ink: NSColor  = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        ink.setFill()
        ink.setStroke()

        ctx.saveGState()
        if params.isWide {
            ctx.translateBy(x: params.walkX, y: 0)
            if params.facingLeft {
                let c = bounds.height / 2
                ctx.translateBy(x: c, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -c, y: 0)
            }
        }

        let s = bounds.height / 18.0
        ctx.scaleBy(x: s, y: s)

        drawBird(ctx: ctx, ink: ink)
        ctx.restoreGState()

        if params.sleeping {
            drawZs(ctx: ctx, ink: ink)
        }
    }

    // Head-only design (like Ollama llama): large head circle fills the frame,
    // prominent curved beak is the defining feature, small crest at back.

    private func drawBird(ctx: CGContext, ink: NSColor) {
        let p = params

        ctx.saveGState()
        ctx.translateBy(x: p.bodyOffsetX + p.bodySway * 0.5,
                        y: p.bodyOffsetY)
        ctx.scaleBy(x: p.bodyScaleX, y: p.bodyScaleY)

        // ── Head (large circle, fills most of frame) ────────────────────
        let headR: CGFloat = 5.5
        let headCenter = NSPoint(x: 7.5, y: 9)
        NSBezierPath(ovalIn: CGRect(x: headCenter.x - headR,
                                     y: headCenter.y - headR,
                                     width: headR * 2,
                                     height: headR * 2)).fill()

        // ── Crest (small feather at upper-left of head) ─────────────────
        let crest = NSBezierPath()
        crest.move(to: NSPoint(x: 3.5, y: 13.5))
        crest.curve(to: NSPoint(x: 2.0, y: 15.5),
                    controlPoint1: NSPoint(x: 3.0, y: 13.5),
                    controlPoint2: NSPoint(x: 2.0, y: 14.5))
        crest.curve(to: NSPoint(x: 3.5, y: 13.0),
                    controlPoint1: NSPoint(x: 2.0, y: 16.0),
                    controlPoint2: NSPoint(x: 2.5, y: 13.5))
        crest.close()
        crest.fill()

        // ── Beak (thick curved hook — THE defining parrot feature) ──────
        if !p.sleeping {
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: headCenter.x + headR - 0.3, y: 10.5))
            beak.curve(to: NSPoint(x: 17.5, y: 10.0),
                       controlPoint1: NSPoint(x: 14.5, y: 12.0),
                       controlPoint2: NSPoint(x: 16.5, y: 12.0))
            beak.curve(to: NSPoint(x: 16.5, y: 6.5),
                       controlPoint1: NSPoint(x: 18.0, y: 8.5),
                       controlPoint2: NSPoint(x: 17.5, y: 7.0))
            beak.line(to: NSPoint(x: headCenter.x + headR - 0.3, y: 8.5))
            beak.close()
            beak.fill()
        }

        // ── Eye ─────────────────────────────────────────────────────────
        if p.sleeping {
            let el = NSBezierPath()
            el.move(to: NSPoint(x: 9.5, y: 10.5))
            el.line(to: NSPoint(x: 11.5, y: 10.5))
            el.lineWidth = 0.9
            el.stroke()
        } else {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let bg = isDark ? NSColor(white: 0.2, alpha: 1) : NSColor.white
            bg.setFill()
            NSBezierPath(ovalIn: CGRect(x: 9.5, y: 9.7, width: 1.8, height: 1.8)).fill()
            ink.setFill()
            NSBezierPath(ovalIn: CGRect(x: 10.0, y: 10.2, width: 0.7, height: 0.7)).fill()
        }

        ctx.restoreGState()
    }

    // MARK: - Sleeping Z's (screen space)

    private func drawZs(ctx: CGContext, ink: NSColor) {
        let t = params.sleepPhase
        let h = bounds.height
        for i in 0 ..< 2 {
            let cycle  = 2.0
            let offset = Double(i) * 1.0
            let phase  = (t + offset).truncatingRemainder(dividingBy: cycle) / cycle
            let alpha: CGFloat
            if      phase < 0.30 { alpha = CGFloat(phase / 0.30) }
            else if phase > 0.70 { alpha = CGFloat((1.0 - phase) / 0.30) }
            else                 { alpha = 1.0 }
            guard alpha > 0.05 else { continue }
            let rise = CGFloat(phase)
            let size = h * (0.22 - CGFloat(i) * 0.05)
            let xPos = h * (0.82 + CGFloat(i) * 0.15)
            let yPos = h * 0.88 + rise * h * 0.25
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: ink.withAlphaComponent(alpha * 0.75)
            ]
            NSAttributedString(string: "z", attributes: attrs).draw(at: CGPoint(x: xPos, y: yPos))
        }
    }
}
