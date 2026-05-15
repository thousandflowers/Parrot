import Foundation
import OSLog

struct FeedbackEntry: Codable {
    let timestamp: Date
    let original: String
    let corrected: String
    let reason: String
    let modelID: String
}

enum FeedbackLogger {
    private static let feedbackDir: URL = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.feedback.error("Cannot access Application Support directory")
            return FileManager.default.temporaryDirectory
        }
        return appSupport.appendingPathComponent("RefineClone")
    }()

    private static let feedbackURL: URL = {
        feedbackDir.appendingPathComponent("feedback.jsonl")
    }()

    private static let maxFileBytes = 10 * 1024 * 1024 // 10 MB
    private static let textTruncationLimit = 500

    static func log(original: String, corrected: String, reason: String = "user_disagrees", modelID: String = "unknown") {
        let truncated = String(original.prefix(textTruncationLimit))
        let correctedTruncated = String(corrected.prefix(textTruncationLimit))
        let entry = FeedbackEntry(
            timestamp: Date(),
            original: truncated,
            corrected: correctedTruncated,
            reason: reason,
            modelID: modelID
        )

        do {
            try FileManager.default.createDirectory(at: feedbackDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: feedbackURL.path(percentEncoded: false)) {
                let attrs = try FileManager.default.attributesOfItem(atPath: feedbackURL.path(percentEncoded: false))
                if let fileSize = attrs[.size] as? Int, fileSize > maxFileBytes {
                    rotateLog()
                }
            }

            let data = try JSONEncoder().encode(entry)
            let line = (String(data: data, encoding: .utf8) ?? "") + "\n"
            if FileManager.default.fileExists(atPath: feedbackURL.path(percentEncoded: false)) {
                let handle = try FileHandle(forWritingTo: feedbackURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let lineData = line.data(using: .utf8) {
                    try handle.write(contentsOf: lineData)
                }
            } else {
                try line.write(to: feedbackURL, atomically: true, encoding: .utf8)
            }
            Logger.feedback.info("Feedback logged: \(reason, privacy: .public)")
        } catch {
            Logger.feedback.error("Failed to write feedback: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func rotateLog() {
        guard let content = try? String(contentsOf: feedbackURL, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 200 else { return }
        let kept = lines.suffix(lines.count - 200).joined(separator: "\n") + "\n"
        try? kept.write(to: feedbackURL, atomically: true, encoding: .utf8)
        Logger.feedback.info("FeedbackLogger: rotated log, removed 200 oldest entries")
    }
}
