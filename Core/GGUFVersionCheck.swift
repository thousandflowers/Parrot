import Foundation
import OSLog

/// Verifies that a GGUF model file is compatible with the current llama-server version.
struct GGUFVersionCheck: Sendable {

    /// Check the GGUF version by reading the file header (first 4KB).
    /// Returns true if the model appears compatible.
    static func isCompatible(filePath: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer {
            do { try handle.close() } catch { Logger.core.debug("GGUF close error: \(error.localizedDescription, privacy: .public)") }
        }

        guard let data = try? handle.read(upToCount: 8), data.count >= 8 else {
            return false
        }
        
        // GGUF Magic (first 4 bytes)
        let magic = String(data: data.subdata(in: 0..<4), encoding: .utf8)
        guard magic == "GGUF" else { return false }
        
        // GGUF Version (next 4 bytes, little endian)
        let versionData = data.subdata(in: 4..<8)
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Current llama.cpp supports v2 and v3
        return version == 2 || version == 3
    }
}
