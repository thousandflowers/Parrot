import Foundation
import Darwin
import OSLog

/// Size-capped, append-only log files (llama-server.log, debug.log, crash.log).
enum LogRotation {
    /// Moves `url` to `<url>.1` (replacing an older backup) when it is larger than `maxBytes`.
    /// Returns true when a rotation happened.
    @discardableResult
    static func rotateIfNeeded(at url: URL, maxBytes: Int) -> Bool {
        let fm = FileManager.default
        let path = url.path(percentEncoded: false)
        guard let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > maxBytes else {
            return false
        }
        let backup = url.appendingPathExtension("1")
        do {
            if fm.fileExists(atPath: backup.path(percentEncoded: false)) {
                try fm.removeItem(at: backup)
            }
            try fm.moveItem(at: url, to: backup)
            return true
        } catch {
            Logger.infra.error("LogRotation: cannot rotate \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Rotates if needed, then opens `url` with O_APPEND (created if missing). O_APPEND also
    /// holds for child processes that inherit the descriptor, so writes never land at offset 0.
    static func openAppendHandle(at url: URL, maxBytes: Int) -> FileHandle? {
        let fd = openAppendFD(at: url, maxBytes: maxBytes)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Raw descriptor variant for code that must stay async-signal-safe (CrashLogger).
    static func openAppendFD(at url: URL, maxBytes: Int) -> Int32 {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateIfNeeded(at: url, maxBytes: maxBytes)
        let fd = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd < 0 {
            Logger.infra.error("LogRotation: cannot open \(url.lastPathComponent, privacy: .public) (errno \(errno, privacy: .public))")
        }
        return fd
    }
}
