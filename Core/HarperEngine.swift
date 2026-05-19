import Foundation
import os

struct HarperFix: Equatable, Sendable {
    let original: String
    let corrected: String
    let message: String
    let category: String
    let byteRange: NSRange
}

struct HarperResult: Sendable {
    let text: String
    let fixes: [HarperFix]
    var hasFixes: Bool { !fixes.isEmpty }
}

actor HarperEngine {
    static let shared = HarperEngine()

    private var binaryURL: URL?
    private let logger = Logger(subsystem: Constants.bundleID, category: "HarperEngine")

    init() {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/harper"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Parrot/harper"),
            URL(fileURLWithPath: "/opt/homebrew/bin/harper"),
            URL(fileURLWithPath: "/usr/local/bin/harper"),
        ]

        for url in candidates.compactMap({ $0 }) {
            if FileManager.default.isExecutableFile(atPath: url.path) {
                binaryURL = url
                logger.info("Harper binary found at \(url.path)")
                return
            }
        }
        logger.warning("Harper binary not found in any known location")
    }

    var isAvailable: Bool { binaryURL != nil }

    func check(_ text: String) async throws -> HarperResult {
        guard let binary = binaryURL else {
            throw HarperError.binaryNotFound
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["lint", "--format", "json"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let inputData = text.data(using: .utf8) ?? Data()
        DispatchQueue.global(qos: .userInitiated).async {
            inputPipe.fileHandleForWriting.write(inputData)
            try? inputPipe.fileHandleForWriting.close()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        let status = process.terminationStatus
        guard status == 0 || status == 1 else {
            throw HarperError.processFailed(status)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let outputString = String(data: outputData, encoding: .utf8),
              !outputString.isEmpty else {
            return HarperResult(text: text, fixes: [])
        }

        let fixes = try parseHarperOutput(outputString, originalText: text)
        let corrected = applyFixes(text, fixes: fixes)

        return HarperResult(text: corrected, fixes: fixes)
    }

    private func parseHarperOutput(_ json: String, originalText: String) throws -> [HarperFix] {
        guard let data = json.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if let jsonData2 = json.data(using: .utf8),
               let single = try? JSONSerialization.jsonObject(with: jsonData2) as? [String: Any],
               let fix = parseSingleFix(single, originalText: originalText) {
                return [fix]
            }
            return []
        }

        return response.compactMap { parseSingleFix($0, originalText: originalText) }
    }

    private func parseSingleFix(_ obj: [String: Any], originalText: String) -> HarperFix? {
        guard let message = obj["message"] as? String,
              let category = obj["category"] as? String,
              let span = obj["span"] as? [String: Any],
              let start = span["start"] as? Int,
              let length = span["length"] as? Int else {
            return nil
        }

        let nsRange = NSRange(location: start, length: length)
        guard let swiftRange = Range(nsRange, in: originalText) else { return nil }
        let original = String(originalText[swiftRange])
        let corrected = (obj["suggestion"] as? String) ?? original

        return HarperFix(original: original, corrected: corrected, message: message, category: category, byteRange: nsRange)
    }

    private func applyFixes(_ text: String, fixes: [HarperFix]) -> String {
        var result = text
        for fix in fixes.reversed() {
            guard let swiftRange = Range(fix.byteRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: fix.corrected)
        }
        return result
    }
}

enum HarperError: Error, LocalizedError {
    case binaryNotFound
    case processFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Harper CLI not found. Install with: cargo install harper-ls"
        case .processFailed(let code):
            return "Harper CLI process failed (exit code: \(code))"
        }
    }
}
