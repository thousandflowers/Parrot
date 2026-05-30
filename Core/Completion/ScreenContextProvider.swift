import Foundation
import Vision
import CoreGraphics
import AppKit
import OSLog

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
    /// Captures the focused app's frontmost window when `pid` is given (cleaner, more relevant, and
    /// faster than the whole display); falls back to the main display.
    func currentContext(pid: pid_t = 0) async -> String {
        if Date().timeIntervalSince(lastCapture) < Constants.completionScreenContextTTL { return cached }
        if capturing { return cached }
        capturing = true
        defer { capturing = false }

        let image = (pid != 0 ? Self.captureFrontWindow(pid: pid) : nil) ?? Self.captureMainDisplay()
        guard let image else { return cached }
        let text = await Self.recognizeText(in: image)
        if !text.isEmpty {
            cached = String(text.suffix(Constants.completionScreenContextMaxChars))
            lastCapture = Date()
        }
        return cached
    }

    /// Captures just the frontmost on-screen window owned by `pid` (the app being typed in).
    private static func captureFrontWindow(pid: pid_t) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Pick the largest normal-layer window belonging to this PID.
        var bestID: CGWindowID?
        var bestArea: CGFloat = 0
        for w in infoList {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let id = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
            if area > bestArea { bestArea = area; bestID = id }
        }
        guard let windowID = bestID else { return nil }
        return CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution])
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
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch {
                Logger.infra.debug("screen OCR failed: \(error.localizedDescription, privacy: .public)")
                cont.resume(returning: "")
            }
        }
    }
}
