import Foundation
import OSLog

/// Manages the LanguageTool CLI JAR lifecycle: check location, download, verify.
enum LanguageToolInstaller {
    private static let logger = Logger(subsystem: Constants.bundleID, category: "LanguageToolInstaller")

    static let ltVersion = "6.5"
    static let downloadURL = URL(string: "https://github.com/languagetool-org/languagetool/releases/download/v\(ltVersion)/languagetool-commandline.jar")!

    static var binaryPath: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Parrot/LanguageTool/languagetool-commandline.jar")
    }

    static var javaPath: URL? {
        let candidates = [
            URL(fileURLWithPath: "/usr/bin/java"),
            URL(fileURLWithPath: "/opt/homebrew/bin/java"),
            URL(fileURLWithPath: "/usr/local/bin/java"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: binaryPath.path) && javaPath != nil
    }

    static func ensureDirectory() throws {
        let dir = binaryPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Download the LanguageTool JAR. Only called on explicit user request.
    static func download(progress: @escaping (Double) -> Void) async throws {
        try ensureDirectory()
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        try FileManager.default.moveItem(at: tempURL, to: binaryPath)
        logger.info("LanguageTool downloaded to \(binaryPath.path)")
    }
}
