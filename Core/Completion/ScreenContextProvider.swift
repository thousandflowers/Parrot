import Foundation
import Vision
import CoreGraphics
import AppKit
import OSLog
import ScreenCaptureKit

/// Reads on-screen text via on-device OCR (Apple Vision) so completion understands context that is
/// NOT in the text field — e.g. the conversation above a chat input, or the email being replied to.
///
/// Throttled (re-OCRs at most every `completionScreenContextTTL` seconds) and run off the main actor
/// so it never stutters typing. Requires Screen Recording permission; degrades to "" without it.
actor ScreenContextProvider {
    static let shared = ScreenContextProvider()

    private var cached: String = ""
    private var lastCapture: Date = .distantPast
    private var capturing = false

    /// Returns recent on-screen text (cached). Empty if unavailable / no permission.
    /// Captures the focused app's frontmost window, then OCRs ONLY the region strictly above the
    /// caret (the conversation/email being replied to) — never the user's input field, which is what
    /// keeps the model from re-reading its own output. Falls back to the whole window when no caret.
    /// `caretRect` is the Cocoa (bottom-left) screen rect; `screenHeight` flips it to image space.
    /// NON-BLOCKING: returns the last OCR result immediately (possibly empty/stale) and, when the
    /// cache is older than the TTL, kicks off a background re-capture+OCR. Completion never waits on
    /// the screen capture, so screen context adds no latency to the suggestion path.
    func currentContext(pid: pid_t = 0, caretRect: CGRect = .zero, screenHeight: CGFloat = 0) -> String {
        if Date().timeIntervalSince(lastCapture) >= Constants.completionScreenContextTTL, !capturing {
            capturing = true
            Task { await self.refresh(pid: pid, caretRect: caretRect, screenHeight: screenHeight) }
        }
        return cached
    }

    /// Captures the front window, crops to above the caret, OCRs, and updates the cache. Runs in the
    /// background off the suggestion path.
    private func refresh(pid: pid_t, caretRect: CGRect, screenHeight: CGFloat) async {
        defer { capturing = false }

        let captured = (pid != 0 ? await Self.captureFrontWindow(pid: pid) : nil)
        guard var img = captured?.image ?? Self.captureMainDisplay() else { return }

        // Crop to above the caret so the input field is excluded.
        if caretRect != .zero, screenHeight > 0, let bounds = captured?.bounds {
            let caretTL = CGRect(x: caretRect.minX, y: screenHeight - caretRect.maxY,
                                 width: caretRect.width, height: caretRect.height)
            if let crop = ScreenCropper.cropAboveCaret(windowBounds: bounds,
                                                       caretRectTopLeft: caretTL,
                                                       imageSize: CGSize(width: img.width, height: img.height)),
               let cropped = img.cropping(to: crop) {
                img = cropped
            }
        }

        let text = await Self.recognizeText(in: img)
        if !text.isEmpty {
            cached = String(text.suffix(Constants.completionScreenContextMaxChars))
            lastCapture = Date()
        }
    }

    /// Captures just the frontmost on-screen window owned by `pid` (the app being typed in), with its
    /// on-screen bounds (points, top-left origin) so the image can be cropped relative to the caret.
    private static func captureFrontWindow(pid: pid_t) async -> (image: CGImage, bounds: CGRect)? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Pick the largest normal-layer window belonging to this PID.
        var bestID: CGWindowID?
        var bestBounds: CGRect = .zero
        var bestArea: CGFloat = 0
        for w in infoList {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let width = b["Width"] ?? 0, height = b["Height"] ?? 0
            let area = width * height
            if area > bestArea {
                bestArea = area; bestID = id
                bestBounds = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: height)
            }
        }
        guard let windowID = bestID else { return nil }
        // ScreenCaptureKit replaces CGWindowListCreateImage (deprecated in macOS 14).
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }),
                  let scDisplay = content.displays.first(where: { $0.frame.contains(bestBounds) })
            else { return nil }
            let filter = SCContentFilter(display: scDisplay, including: [scWindow])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: SCStreamConfiguration())
            return (image, bestBounds)
        } catch {
            return nil
        }
    }

    /// Asks for Screen Recording permission (no-op if already granted).
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    private static func captureMainDisplay() -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let displayID = CGMainDisplayID()
        return CGDisplayCreateImage(displayID)
    }

    private static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                // Sort observations into reading order (top → bottom) so the joined text is the
                // actual content flow, and the TAIL is what's nearest the input field.
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = obs
                    .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }   // higher on screen first
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { $0.trimmingCharacters(in: .whitespaces).count >= 2 }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .fast      // speed over accuracy — context, not transcription
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch {
                Logger.infra.debug("screen OCR failed: \(error.localizedDescription, privacy: .public)")
                cont.resume(returning: "")
            }
        }
    }
}
