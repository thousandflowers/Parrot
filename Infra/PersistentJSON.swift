import Foundation
import OSLog

/// Shared load path for the JSON-file stores (rules, contacts, history, snippets, KB…).
///
/// A file that exists but cannot be read or decoded is never treated as "empty": it is
/// moved aside to `<name>.corrupt-<timestamp>.json` before the caller starts with an empty
/// store, so the next save cannot overwrite the user's data.
enum PersistentJSON {
    /// Returns the decoded value, or nil when the file is missing or was quarantined.
    static func load<T: Decodable>(_ type: T.Type, from url: URL, now: Date = Date(),
                                   decoder: JSONDecoder = JSONDecoder()) -> T? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            Logger.infra.error("PersistentJSON: cannot load \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            quarantine(url, now: now)
            return nil
        }
    }

    /// `<dir>/<stem>.corrupt-<yyyyMMdd-HHmmss>.<ext>`
    static func quarantineURL(for url: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).corrupt-\(formatter.string(from: date)).\(ext)")
    }

    private static func quarantine(_ url: URL, now: Date) {
        let fm = FileManager.default
        let preferred = quarantineURL(for: url, at: now)
        let target = fm.fileExists(atPath: preferred.path(percentEncoded: false))
            ? uniqued(preferred)
            : preferred
        do {
            try fm.moveItem(at: url, to: target)
            Logger.infra.error("PersistentJSON: moved unreadable \(url.lastPathComponent, privacy: .public) to \(target.lastPathComponent, privacy: .public)")
            CrashLogger.log("Unreadable data file \(url.lastPathComponent) preserved as \(target.lastPathComponent)")
        } catch {
            Logger.infra.fault("PersistentJSON: could not preserve \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            CrashLogger.log("FAILED to preserve unreadable data file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func uniqued(_ url: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = UUID().uuidString.prefix(8)
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-\(suffix).\(url.pathExtension)")
    }
}
