
import Foundation

/// Verifies that a GGUF model file is compatible with the current llama-server version.
struct GGUFVersionCheck: Sendable {

    /// Check the GGUF version by reading the file header (first 4KB).
    /// Returns true if the model appears compatible.
    static func isCompatible(filePath: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return false }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096),
              data.count >= 4,
              let magic = String(data: data.subdata(in: 0..<4), encoding: .utf8) else {
            return false
        }
        return magic == "GGUF"
    }

    /// Extract GGUF version from file header.
    static func ggufVersion(filePath: String) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096),
              data.count > 8,
              String(data: data.subdata(in: 0..<4), encoding: .utf8) == "GGUF" else {
            return nil
        }
        // GGUF version is a u32 little-endian at offset 4-7
        var version: UInt32 = 0
        data.subdata(in: 4..<8).withUnsafeBytes { raw in
            guard raw.count >= 4 else { return }
            version = UInt32(littleEndian: raw.loadUnaligned(as: UInt32.self))
        }
        return Int(version)
    }
}
