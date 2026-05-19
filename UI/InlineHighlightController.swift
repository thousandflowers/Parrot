import Cocoa
import os

@MainActor
final class InlineHighlightController {
    static let shared = InlineHighlightController()
    private init() {}

    private var underlayWindow: NSWindow?
    private var overlayView: UnderlineOverlayView?
    private var setupTask: Task<Void, Never>?

    // Stored rects for hover detection (screen/AppKit coordinates)
    private var annotationRects: [(rect: CGRect, annotation: ErrorAnnotation)] = []
    private var trackedPID: pid_t = 0
    private var mouseMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?

    func show(_ annotations: [ErrorAnnotation], pid: pid_t) {
        clear()
        guard !annotations.isEmpty else { return }
        trackedPID = pid
        setupTask = Task { await setupOverlay(annotations, pid: pid) }
    }

    func clear() {
        setupTask?.cancel()
        hideTask?.cancel()
        applyTask?.cancel()
        applyTask = nil
        stopMouseTracking()
        underlayWindow?.orderOut(nil)
        underlayWindow = nil
        overlayView = nil
        annotationRects = []
        HoverAnnotationPopup.shared.hide()
    }

    /// Applica tutte le annotazioni in ordine inverso (dalla fine al fronte del testo)
    /// per non invalidare gli offset delle annotazioni precedenti.
    func applyAllAnnotations() {
        let pid = trackedPID
        let toApply = annotationRects
            .map { $0.annotation }
            .filter { !$0.suggestedFix.isEmpty }
            .sorted { $0.charRange.location > $1.charRange.location }

        guard !toApply.isEmpty else { return }

        applyTask = Task {
            for annotation in toApply {
                guard !Task.isCancelled else { return }
                try? await AccessibilityBridge.shared.replaceRange(
                    annotation.charRange,
                    with: annotation.suggestedFix,
                    pid: pid
                )
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.clear()
                SuggestionPanelController.shared.close()
            }
        }
    }

    private func setupOverlay(_ annotations: [ErrorAnnotation], pid: pid_t) async {
        var rects: [(CGRect, ErrorAnnotation)] = []
        for ann in annotations {
            if let r = await AccessibilityBridge.shared.boundsForRange(ann.charRange, pid: pid) {
                rects.append((r, ann))
            }
        }
        guard !rects.isEmpty else { return }
        guard !Task.isCancelled else { return }

        annotationRects = rects

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
            items: rects.map { ($0.0, $0.1.severity) }
        )
        overlayView = view
        underlay.contentView = view
        underlay.orderFrontRegardless()
        underlayWindow = underlay

        startMouseTracking()
    }

    // MARK: - Mouse tracking

    private func startMouseTracking() {
        stopMouseTracking()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.type == .leftMouseDown {
                    self.handleMouseDown(at: NSEvent.mouseLocation)
                } else {
                    self.handleMouseMoved(at: NSEvent.mouseLocation)
                }
            }
        }
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func handleMouseMoved(at location: NSPoint) {
        // Don't hide if mouse is over the popup itself
        if HoverAnnotationPopup.shared.isVisible,
           HoverAnnotationPopup.shared.windowFrame.contains(location) {
            hideTask?.cancel()
            return
        }

        // Check annotation rects
        for (rect, annotation) in annotationRects {
            if rect.contains(location) {
                hideTask?.cancel()
                HoverAnnotationPopup.shared.show(annotation: annotation, pid: trackedPID, near: rect)
                return
            }
        }

        // Not over anything — schedule hide with small delay so user can move to popup
        scheduleHide()
    }

    private func handleMouseDown(at location: NSPoint) {
        // If clicking the popup's checkmark the popup handles it.
        // If clicking elsewhere clear everything.
        if HoverAnnotationPopup.shared.isVisible,
           HoverAnnotationPopup.shared.windowFrame.contains(location) {
            return
        }
        // Click outside annotations: clear
        for (rect, _) in annotationRects {
            if rect.contains(location) { return }
        }
        clear()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            // Re-check before hiding
            let loc = NSEvent.mouseLocation
            if let self = self {
                if HoverAnnotationPopup.shared.isVisible,
                   HoverAnnotationPopup.shared.windowFrame.contains(loc) { return }
                for (rect, _) in self.annotationRects {
                    if rect.contains(loc) { return }
                }
                HoverAnnotationPopup.shared.hide()
            }
        }
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
