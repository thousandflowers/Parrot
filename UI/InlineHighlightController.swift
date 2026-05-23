import Cocoa
import os

@MainActor
final class InlineHighlightController {
    static let shared = InlineHighlightController()
    private init() {}

    private var underlayWindow: NSWindow?
    private var overlayView: UnderlineOverlayView?
    private var setupTask: Task<Void, Never>?

    private var storedAnnotations: [ErrorAnnotation] = []
    private var storedRects: [(rect: CGRect, annotation: ErrorAnnotation)] = []

    // Stored rects for hover detection (screen/AppKit coordinates)
    private var annotationRects: [(rect: CGRect, annotation: ErrorAnnotation)] = []
    private var trackedPID: pid_t = 0
    private var mouseMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?

    private var hoverOnlyMode: Bool { PreferencesStore.shared.inlineAnnotationsHoverOnly }

    func show(_ annotations: [ErrorAnnotation], pid: pid_t) {
        clear()
        guard !annotations.isEmpty else { return }
        trackedPID = pid
        storedAnnotations = annotations

        if hoverOnlyMode {
            computeRects { [weak self] rects in
                Task { @MainActor [weak self] in
                    guard let self, !rects.isEmpty else { return }
                    self.storedRects = rects
                    self.startMouseTracking()
                }
            }
        } else {
            setupTask = Task { await setupOverlay(annotations, pid: pid) }
        }
    }

    private func computeRects(completion: @escaping @Sendable ([(CGRect, ErrorAnnotation)]) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { completion([]); return }
            var rects: [(CGRect, ErrorAnnotation)] = []
            for ann in storedAnnotations {
                if let r = await AccessibilityBridge.shared.boundsForRange(ann.charRange, pid: trackedPID) {
                    rects.append((r, ann))
                }
            }
            completion(rects)
        }
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
        storedRects = []
        storedAnnotations = []
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
            var failures = 0
            for annotation in toApply {
                guard !Task.isCancelled else { return }
                do {
                    try await AccessibilityBridge.shared.replaceRange(
                        annotation.charRange,
                        with: annotation.suggestedFix,
                        pid: pid
                    )
                } catch {
                    failures += 1
                }
            }
            if failures > 0 {
                Logger.ui.debug("InlineHighlightController: \(failures, privacy: .public)/\(toApply.count, privacy: .public) replacements failed")
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

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
        if hoverOnlyMode {
            handleHoverOnlyMouseMoved(at: location)
            return
        }

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

    private func handleHoverOnlyMouseMoved(at location: NSPoint) {
        if HoverAnnotationPopup.shared.isVisible,
           HoverAnnotationPopup.shared.windowFrame.contains(location) {
            hideTask?.cancel()
            return
        }

        for (rect, annotation) in storedRects {
            if rect.contains(location) {
                hideTask?.cancel()
                if underlayWindow == nil {
                    showOverlayForRects(storedRects)
                }
                HoverAnnotationPopup.shared.show(annotation: annotation, pid: trackedPID, near: rect)
                return
            }
        }

        scheduleHide()
    }

    private func showOverlayForRects(_ rects: [(CGRect, ErrorAnnotation)]) {
        guard !rects.isEmpty else { return }
        annotationRects = rects.map { ($0.0, $0.1) }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
    }

    private func handleMouseDown(at location: NSPoint) {
        if HoverAnnotationPopup.shared.isVisible,
           HoverAnnotationPopup.shared.windowFrame.contains(location) {
            return
        }
        for (rect, _) in (hoverOnlyMode ? storedRects : annotationRects) {
            if rect.contains(location) { return }
        }
        clear()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let loc = NSEvent.mouseLocation
            if let self = self {
                if HoverAnnotationPopup.shared.isVisible,
                   HoverAnnotationPopup.shared.windowFrame.contains(loc) { return }
                let rects = self.hoverOnlyMode ? self.storedRects : self.annotationRects
                for (rect, _) in rects {
                    if rect.contains(loc) { return }
                }
                HoverAnnotationPopup.shared.hide()
                if self.hoverOnlyMode {
                    self.underlayWindow?.orderOut(nil)
                    self.underlayWindow = nil
                    self.overlayView = nil
                    self.annotationRects = []
                }
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

    @available(*, unavailable, message: "Use init() instead")
    required init?(coder: NSCoder) { fatalError("InlineHighlightController does not support storyboard decoding") }

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
