import Foundation
import os

struct HarperFix: Equatable, Sendable {
    let original: String
    let corrected: String
    let message: String
    let category: String
    /// UTF-16 range in the checked text (converted from Harper's scalar offsets).
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
            AppPaths.applicationSupport?
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

    /// Harper is a local lint pass that normally answers in well under a second; anything
    /// slower is a hung process and must not hold up the correction.
    static let processTimeoutSeconds: TimeInterval = 5

    func check(_ text: String) async throws -> HarperResult {
        guard let binary = binaryURL else {
            throw HarperError.binaryNotFound
        }

        let (status, outputData) = try await Self.runProcess(
            binary: binary, arguments: ["lint", "--format", "json"],
            input: Data(text.utf8), timeout: Self.processTimeoutSeconds)
        guard status == 0 || status == 1 else {
            throw HarperError.processFailed(status)
        }
        guard let outputString = String(data: outputData, encoding: .utf8),
              !outputString.isEmpty else {
            return HarperResult(text: text, fixes: [])
        }

        let fixes = try parseHarperOutput(outputString, originalText: text)
        let corrected = applyFixes(text, fixes: fixes)

        return HarperResult(text: corrected, fixes: fixes)
    }

    /// Runs the CLI without the classic Process deadlocks: stdin is written and stdout drained
    /// on background queues (a >64 KB output can't block the child), the result is resumed
    /// exactly once, and a timeout or task cancellation terminates the child.
    private static func runProcess(
        binary: URL, arguments: [String], input: Data, timeout: TimeInterval
    ) async throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        let gate = ProcessResumeGate(process: process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                do {
                    try process.run()
                } catch {
                    gate.resume(.failure(error))
                    return
                }
                let writer = inputPipe.fileHandleForWriting
                // A child that exits without reading stdin must not SIGPIPE the whole app.
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                DispatchQueue.global(qos: .userInitiated).async {
                    try? writer.write(contentsOf: input)
                    try? writer.close()
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
                    process.waitUntilExit()
                    gate.resume(.success((process.terminationStatus, data)))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    gate.terminate(with: HarperError.timedOut)
                }
            }
        } onCancel: {
            gate.terminate(with: CancellationError())
        }
    }

    /// Harper spans count Rust `char`s (Unicode scalars); CorrectionSpan / NSString need
    /// UTF-16. Returns nil when the span falls outside the text.
    static func utf16Range(scalarStart: Int, scalarLength: Int, in text: String) -> NSRange? {
        let scalars = text.unicodeScalars
        guard scalarStart >= 0, scalarLength >= 0,
              let start = scalars.index(scalars.startIndex, offsetBy: scalarStart, limitedBy: scalars.endIndex),
              let end = scalars.index(start, offsetBy: scalarLength, limitedBy: scalars.endIndex)
        else { return nil }
        return NSRange(start..<end, in: text)
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
              let length = (span["length"] as? Int) ?? (span["end"] as? Int).map({ $0 - start }) else {
            return nil
        }

        guard let nsRange = Self.utf16Range(scalarStart: start, scalarLength: length, in: originalText),
              let swiftRange = Range(nsRange, in: originalText) else { return nil }
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

/// Resumes a process continuation exactly once, whichever of exit / timeout / cancellation
/// comes first, and terminates the child on timeout or cancellation.
private final class ProcessResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var continuation: CheckedContinuation<(status: Int32, output: Data), Error>?
    private var pendingError: Error?

    init(process: Process) { self.process = process }

    /// Returns false (and fails the continuation) when cancellation already happened.
    func install(_ continuation: CheckedContinuation<(status: Int32, output: Data), Error>) -> Bool {
        lock.lock()
        if let error = pendingError {
            lock.unlock()
            continuation.resume(throwing: error)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resume(_ result: Result<(status: Int32, output: Data), Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        if pending == nil, case .failure(let error) = result { pendingError = pendingError ?? error }
        lock.unlock()
        pending?.resume(with: result)
    }

    func terminate(with error: Error) {
        if process.isRunning { process.terminate() }
        resume(.failure(error))
    }
}

enum HarperError: Error, LocalizedError {
    case binaryNotFound
    case processFailed(Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Harper CLI did not answer in time"
        case .binaryNotFound:
            return "Harper CLI not found. Install with: cargo install harper-ls"
        case .processFailed(let code):
            return "Harper CLI process failed (exit code: \(code))"
        }
    }
}
