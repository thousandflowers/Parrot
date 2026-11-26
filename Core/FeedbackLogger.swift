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
        guard let appSupport = AppPaths.applicationSupport else {
            Logger.feedback.error("Cannot access Application Support directory")
            return FileManager.default.temporaryDirectory
        }
        return appSupport.appendingPathComponent("Parrot")
    }()

    private static let feedbackURL: URL = {
        feedbackDir.appendingPathComponent("feedback.jsonl")
    }()

    private static let maxFileBytes = 10 * 1024 * 1024 // 10 MB
    private static let textTruncationLimit = 500
    private static let queue = DispatchQueue(label: "\(Constants.bundleID).feedback", qos: .background)

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
        queue.async { writeEntry(entry) }
    }

    private static func writeEntry(_ entry: FeedbackEntry) {
        do {
            try FileManager.default.createDirectory(at: feedbackDir, withIntermediateDirectories: true)

            let path = feedbackURL.path(percentEncoded: false)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let fileSize = attrs[.size] as? Int, fileSize > maxFileBytes {
                rotateLog()
            }

            let data = try JSONEncoder().encode(entry)
            guard let lineData = ((String(data: data, encoding: .utf8) ?? "") + "\n").data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: feedbackURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
            } else {
                try lineData.write(to: feedbackURL, options: .atomic)
            }
            Logger.feedback.info("Feedback logged: \(entry.reason, privacy: .public)")
        } catch {
            Logger.feedback.error("Failed to write feedback: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func recentEntries(limit: Int = 30) -> [FeedbackEntry] {
        guard let content = try? String(contentsOf: feedbackURL, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let decoder = JSONDecoder()
        return lines.suffix(limit).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(FeedbackEntry.self, from: data)
        }
    }

    /// Reads the whole (≤ ~10 MB) log once and keeps the newest whole lines within half the
    /// cap, so rotation runs rarely and never splits a line or a UTF-8 sequence.
    private static func rotateLog() {
        do {
            let data = try Data(contentsOf: feedbackURL, options: .mappedIfSafe)
            let kept = trimmedLog(data, keepingAtMostBytes: maxFileBytes / 2)
            try kept.write(to: feedbackURL, atomically: true, encoding: .utf8)
            Logger.feedback.info("FeedbackLogger: rotated log \(data.count, privacy: .public) → \(kept.utf8.count, privacy: .public) bytes")
        } catch {
            Logger.feedback.error("FeedbackLogger: rotation failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Newest complete lines of `data` whose total size (with newlines) fits `budget` bytes.
    static func trimmedLog(_ data: Data, keepingAtMostBytes budget: Int) -> String {
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        var kept: [Substring] = []
        var total = 0
        for line in lines.reversed() {
            let cost = line.utf8.count + 1
            guard total + cost <= budget else { break }
            kept.append(line)
            total += cost
        }
        guard !kept.isEmpty else { return "" }
        return kept.reversed().joined(separator: "\n") + "\n"
    }
}
