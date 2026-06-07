import AppKit
import OSLog

/// Inline ghost-text overlay that shows a correction at the original text's position.
/// Reuses the same approach as CompletionOverlayWindow but positioned at the selection
/// bounds instead of caret, and with cycle/accept/dismiss keyboard controls.
@MainActor
final class RewriteOverlayWindow {
    private var panel: NSPanel?
    private var alternatives: [String] = []
    private var currentIndex: Int = 0
    private var originalText: String = ""
    private var pid: pid_t = 0

    private let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        l.lineBreakMode = .byClipping
        l.setAccessibilityElement(true)
        l.setAccessibilityRole(.staticText)
        return l
    }()

    private var altLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        l.font = .systemFont(ofSize: 10, weight: .medium)
        l.textColor = NSColor.secondaryLabelColor
        l.alignment = .center
        l.setAccessibilityElement(false)
        return l
    }()

    var hasActiveRewrite: Bool { panel != nil }
    var currentCorrection: String { alternatives.isEmpty ? "" : alternatives[currentIndex] }

    /// Show correction inline at the selection bounds. `alternatives` = multiple rewrites (same text,
    /// different seeds), first one shown. User cycles with ⌘+Tab, accepts with Tab, dismisses with Esc.
    func show(original: String, corrected: String, alternatives altList: [String] = [],
              at rect: CGRect, pid: pid_t) {
        guard rect != .zero, !rect.isInfinite, !rect.isNull, !corrected.isEmpty else { return }
        self.originalText = original
        self.alternatives = altList.isEmpty ? [corrected] : [corrected] + altList
        self.currentIndex = 0
        self.pid = pid
        updateLabel()

        let panel = ensurePanel()
        let altCount = self.alternatives.count
        altLabel.stringValue = altCount > 1 ? "\(1)/\(altCount)" : ""
        altLabel.sizeToFit()

        label.sizeToFit()
        let labelSize = label.frame.size
        let padX: CGFloat = 8
        let padY: CGFloat = 4
        let altH: CGFloat = altCount > 1 ? 16 : 0
        let panelW = max(labelSize.width + padX * 2, altCount > 1 ? 80 : 0)
        let panelH = labelSize.height + padY * 2 + altH

        var origin = CGPoint(x: rect.minX, y: rect.minY - padY)
        let caretPoint = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(caretPoint) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            if origin.x + panelW > vf.maxX { origin.x = max(vf.minX, vf.maxX - panelW) }
            if origin.x < vf.minX { origin.x = vf.minX }
            if origin.y + panelH > vf.maxY { origin.y = vf.maxY - panelH }
            if origin.y < vf.minY { origin.y = vf.minY }
        }
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: panelW, height: panelH)), display: true)
        label.frame = CGRect(x: padX, y: padY + altH, width: labelSize.width, height: labelSize.height)
        altLabel.frame = CGRect(x: padX, y: 2, width: panelW - padX * 2, height: 14)

        panel.setAccessibilityLabel("Rewrite: \(corrected.prefix(120))")
        NSAccessibility.post(element: panel, notification: .announcementRequested)
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
    }

    func cycleNext() {
        guard alternatives.count > 1 else { return }
        currentIndex = (currentIndex + 1) % alternatives.count
        updateLabel()
        altLabel.stringValue = "\(currentIndex + 1)/\(alternatives.count)"
        altLabel.sizeToFit()
        if let panel { NSAccessibility.post(element: panel, notification: .announcementRequested) }
    }

    func cyclePrev() {
        guard alternatives.count > 1 else { return }
        currentIndex = (currentIndex - 1 + alternatives.count) % alternatives.count
        updateLabel()
        altLabel.stringValue = "\(currentIndex + 1)/\(alternatives.count)"
        altLabel.sizeToFit()
        if let panel { NSAccessibility.post(element: panel, notification: .announcementRequested) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        alternatives = []
        currentIndex = 0
        originalText = ""
        pid = 0
    }

    private func updateLabel() {
        let text = currentCorrection
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.count)
        let size = NSFont.systemFontSize(for: .regular)
        let baseFont = NSFont.systemFont(ofSize: size)
        attributed.addAttribute(.font, value: baseFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: NSColor.ghostTextHighlight, range: fullRange)
        label.attributedStringValue = attributed
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.setAccessibilityElement(true)
        p.setAccessibilityRole(.staticText)

        let blur = NSVisualEffectView()
        blur.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .underPageBackground : .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 6
        blur.layer?.masksToBounds = true
        blur.addSubview(altLabel)
        blur.addSubview(label)
        label.setAccessibilityElement(false)
        p.contentView = blur
        panel = p
        return p
    }
}

/// Manages inline rewrite state: alternatives, accept/cycle/dismiss.
@MainActor
final class RewriteController {
    static let shared = RewriteController()

    private let overlay = RewriteOverlayWindow()
    private var currentOriginal: String = ""
    private var currentPID: pid_t = 0
    private var anchorRect: CGRect = .zero
    private var pendingTask: Task<Void, Never>?

    private init() {}

    var isActive: Bool { overlay.hasActiveRewrite }
    var currentCorrection: String { overlay.currentCorrection }

    /// Show correction inline with alternatives. The show closure is responsible for generating
    /// multiple alternatives via the LLM.
    func showInline(original: String, correction: String, alternatives: [String] = [],
                    at rect: CGRect, pid: pid_t) {
        currentOriginal = original
        currentPID = pid
        anchorRect = rect
        overlay.show(original: original, corrected: correction, alternatives: alternatives,
                     at: rect, pid: pid)
        RewriteActiveFlag.set(true)
    }

    func cycleNext() {
        guard isActive else { return }
        overlay.cycleNext()
    }

    func cyclePrev() {
        guard isActive else { return }
        overlay.cyclePrev()
    }

    /// Accept the current correction: replace the original text with the correction.
    func accept() {
        guard isActive, currentPID != 0 else { return }
        let text = overlay.currentCorrection
        dismiss()
        Task {
            try? await AccessibilityBridge.shared.replaceSelectedText(with: text)
            await StatsStore.shared.recordAccepted(text: text)
            await MainActor.run { DirectApplyToast.show(message: "✓ Replaced") }
            Logger.infra.debug("rewrite-inline: accepted replacement")
            // Re-arm completion pipeline so the ghost overlay re-appears for the
            // next word — don't rely solely on the AX value-changed event (which
            // can be delayed or missed with clipboard-based injection).
            await MainActor.run { CompletionController.shared.textChanged() }
        }
    }

    /// Dismiss the overlay without applying.
    func dismiss() {
        RewriteActiveFlag.set(false)
        overlay.hide()
        currentOriginal = ""
        currentPID = 0
        anchorRect = .zero
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// Generate alternatives by re-requesting the LLM with different sampling parameters.
    func generateAlternatives(text: String, promptType: PromptType, serviceType: ServiceType?,
                              count: Int = 2) async -> [String] {
        var results: [String] = []
        for _ in 0..<count {
            do {
                let result = try await RequestQueue.shared.enqueue(
                    text: text, type: promptType, priority: .manual,
                    overrideServiceType: serviceType, overrideCustomPrompt: nil
                )
                if result.hasChanges {
                    results.append(result.correctedText)
                }
            } catch {
                CrashLogger.log("rewrite-alt: generation failed — \(error.localizedDescription)")
            }
        }
        return results
    }
}

/// Atomic flag for TapInterceptor to check whether rewrite mode is active.
/// Uses NSLock for thread safety (OSAllocatedUnfairLock unavailable on older macOS).
enum RewriteActiveFlag {
    nonisolated(unsafe) private static var _active = false
    nonisolated private static let lock = NSLock()

    nonisolated static var isActive: Bool { lock.withLock { _active } }
    nonisolated static func set(_ v: Bool) { lock.withLock { _active = v } }
}
