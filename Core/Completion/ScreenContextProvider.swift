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
    func currentContext() async -> String {
        if Date().timeIntervalSince(lastCapture) < Constants.completionScreenContextTTL { return cached }
        if capturing { return cached }
        capturing = true
        defer { capturing = false }

        guard let image = Self.captureMainDisplay() else { return cached }
        let text = await Self.recognizeText(in: image)
        if !text.isEmpty {
            cached = String(text.suffix(Constants.completionScreenContextMaxChars))
            lastCapture = Date()
        }
        return cached
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
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
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
