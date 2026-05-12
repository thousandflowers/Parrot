import Foundation
import os

/// Verifies that a GGUF model file is compatible with the current llama-server version.
struct GGUFVersionCheck: Sendable {

    /// Check the GGUF version by reading the file header (first 4KB).
    /// Returns true if the model appears compatible.
    static func isCompatible(filePath: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer {
            do { try handle.close() } catch { os_log(.debug, "GGUF close error: %{public}@", error.localizedDescription) }
        }

        guard let data = try? handle.read(upToCount: 4096),
              data.count >= 4,
              let magic = String(data: data.subdata(in: 0..<4), encoding: .utf8) else {
            return false
        }
        return magic == "GGUF"
    }
}
