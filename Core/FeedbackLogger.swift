import Foundation
import os

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
            os_log(.error, "Cannot access Application Support directory")
            return FileManager.default.temporaryDirectory
        }
        return appSupport.appendingPathComponent("RefineClone")
    }()

    private static let feedbackURL: URL = {
        feedbackDir.appendingPathComponent("feedback.jsonl")
    }()

    static func log(original: String, corrected: String, reason: String = "user_disagrees", modelID: String = "unknown") {
        let entry = FeedbackEntry(
            timestamp: Date(),
            original: original,
            corrected: corrected,
            reason: reason,
            modelID: modelID
        )

        do {
            try FileManager.default.createDirectory(at: feedbackDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            var line = String(data: data, encoding: .utf8) ?? ""
            line += "\n"
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
            os_log(.info, "Feedback logged: %{public}@", reason)
        } catch {
            os_log(.error, "Failed to write feedback: %{public}@", error.localizedDescription)
        }
    }
}
