import Foundation
import os

struct HarperFix: Equatable, Sendable {
    let original: String
    let corrected: String
    let message: String
    let category: String
}

struct HarperResult: Sendable {
    let text: String
    let fixes: [HarperFix]
    var hasFixes: Bool { !fixes.isEmpty }
}

actor HarperEngine {
    static let shared = HarperEngine()

    private var binaryURL: URL?
    private let logger = Logger(subsystem: "com.thousandflowers.refineclone", category: "HarperEngine")

    init() {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/harper"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("RefineClone/harper"),
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
        process.standardError = Pipe()

        try process.run()

        let inputData = text.data(using: .utf8) ?? Data()
        inputPipe.fileHandleForWriting.write(inputData)
        try inputPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HarperError.processFailed(process.terminationStatus)
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
            if let single = try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any],
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

        return HarperFix(original: original, corrected: corrected, message: message, category: category)
    }

    private func applyFixes(_ text: String, fixes: [HarperFix]) -> String {
        var result = text
        for fix in fixes.reversed() {
            if let range = result.range(of: fix.original) {
                result.replaceSubrange(range, with: fix.corrected)
            }
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
            return "Harper CLI non trovato. Installa con: cargo install harper-ls"
        case .processFailed(let code):
            return "Harper CLI ha restituito errore (codice: \(code))"
        }
    }
}
