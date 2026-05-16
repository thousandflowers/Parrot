import Cocoa
import os

@MainActor
final class InlineHighlightController {
    static let shared = InlineHighlightController()
    private init() {}

    private var underlayWindow: NSWindow?
    private var overlayView: UnderlineOverlayView?
    private var setupTask: Task<Void, Never>?

    func show(_ annotations: [ErrorAnnotation], pid: pid_t) {
        clear()
        guard !annotations.isEmpty else { return }
        setupTask = Task { await setupOverlay(annotations, pid: pid) }
    }

    func clear() {
        setupTask?.cancel()
        underlayWindow?.orderOut(nil)
        underlayWindow = nil
        overlayView = nil
    }

    private func setupOverlay(_ annotations: [ErrorAnnotation], pid: pid_t) async {
        var rects: [(CGRect, ErrorSeverity)] = []
        for ann in annotations {
            if let r = await AccessibilityBridge.shared.boundsForRange(ann.charRange, pid: pid) {
                rects.append((r, ann.severity))
            }
        }
        guard !rects.isEmpty else { return }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame

        let underlay = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        underlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        underlay.backgroundColor = .clear
        underlay.isOpaque = false
        underlay.ignoresMouseEvents = true
        underlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = UnderlineOverlayView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            items: rects
        )
        overlayView = view
        underlay.contentView = view
        underlay.orderFrontRegardless()
        underlayWindow = underlay
    }
}

// MARK: - Wavy underline overlay

final class UnderlineOverlayView: NSView {
    private var items: [(rect: CGRect, severity: ErrorSeverity)]

    init(frame: NSRect, items: [(CGRect, ErrorSeverity)]) {
        self.items = items
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(items: [(CGRect, ErrorSeverity)]) {
        self.items = items
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let winOrigin = window?.frame.origin ?? .zero
        for (rect, severity) in items {
            let viewRect = CGRect(
                x: rect.origin.x - winOrigin.x,
                y: rect.origin.y - winOrigin.y,
                width: rect.width, height: rect.height
            )
            drawWavy(in: viewRect, color: severity.nsColor)
        }
    }

    private func drawWavy(in rect: CGRect, color: NSColor) {
        let path = NSBezierPath()
        let y = rect.minY
        let amplitude: CGFloat = 1.5
        let halfPeriod: CGFloat = 4.0
        var x = rect.minX
        var up = true
        path.move(to: CGPoint(x: x, y: y))
        while x < rect.maxX {
            let nx = min(x + halfPeriod, rect.maxX)
            let dx = nx - x
            let cy = y + (up ? amplitude : -amplitude)
            path.curve(to: CGPoint(x: nx, y: y),
                       controlPoint1: CGPoint(x: x + dx * 0.25, y: cy),
                       controlPoint2: CGPoint(x: x + dx * 0.75, y: cy))
            x = nx; up.toggle()
        }
        color.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
