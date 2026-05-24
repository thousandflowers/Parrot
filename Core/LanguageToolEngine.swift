import Foundation
import OSLog

actor LanguageToolEngine {
    static let shared = LanguageToolEngine()
    private let logger = Logger(subsystem: Constants.bundleID, category: "LanguageToolEngine")

    var isAvailable: Bool { LanguageToolInstaller.isAvailable }

    /// Map Parrot language codes to LanguageTool locale codes.
    nonisolated static func ltLanguageCode(for language: String) -> String {
        let primary = language.split(separator: "-").first.map(String.init) ?? language
        switch primary {
        case "it":        return "it-IT"
        case "en":        return "en-US"
        case "fr":        return "fr-FR"
        case "de":        return "de-DE"
        case "es":        return "es-ES"
        case "pt":        return "pt-BR"
        case "ru":        return "ru-RU"
        case "pl":        return "pl-PL"
        case "uk":        return "uk-UA"
        case "nl":        return "nl-NL"
        case "sv":        return "sv-SE"
        case "da":        return "da-DK"
        case "nb", "no":  return "nb-NO"
        case "ca":        return "ca-ES"
        case "el":        return "el-GR"
        case "ro":        return "ro-RO"
        case "sk":        return "sk-SK"
        case "sl":        return "sl-SI"
        case "zh", "yue": return "zh-CN"
        case "ja":        return "ja-JP"
        case "ar":        return "ar"
        case "fa":        return "fa"
        default:          return language
        }
    }

    /// Run LanguageTool locally on `text` and return correction spans.
    func check(_ text: String, language: String) async throws -> [CorrectionSpan] {
        guard isAvailable else { return [] }
        guard let java = LanguageToolInstaller.javaPath else { return [] }

        let ltCode = Self.ltLanguageCode(for: language)
        let process = Process()
        process.executableURL = java
        process.arguments = [
            "-jar", LanguageToolInstaller.binaryPath.path,
            "--language", ltCode,
            "--json",
            "-"
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let inputData = text.data(using: .utf8) ?? Data()
        DispatchQueue.global(qos: .userInitiated).async {
            inputPipe.fileHandleForWriting.write(inputData)
            try? inputPipe.fileHandleForWriting.close()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        guard process.terminationStatus == 0 else {
            logger.warning("LT exited with status \(process.terminationStatus)")
            return []
        }

        let outputData = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
        guard let json = String(data: outputData, encoding: .utf8) else { return [] }
        return parseLTOutput(json, originalText: text)
    }

    // MARK: - Parser

    private func parseLTOutput(_ json: String, originalText: String) -> [CorrectionSpan] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let matches = root["matches"] as? [[String: Any]]
        else { return [] }

        var spans: [CorrectionSpan] = []
        for match in matches {
            guard
                let offset = match["offset"] as? Int,
                let length = match["length"] as? Int,
                let message = match["message"] as? String,
                let replacements = match["replacements"] as? [[String: Any]],
                let firstValue = replacements.first?["value"] as? String
            else { continue }

            let nsRange = NSRange(location: offset, length: length)
            guard let swiftRange = Range(nsRange, in: originalText) else { continue }
            let original = String(originalText[swiftRange])
            guard original != firstValue else { continue }

            spans.append(CorrectionSpan(
                range: nsRange,
                original: original,
                replacement: firstValue,
                reason: message,
                confidence: 0.95,
                source: .languageTool
            ))
        }
        return spans
    }
}
