import Foundation

/// Detects whether text is rough draft notes vs. polished prose.
/// Uses only language-agnostic statistical signals — no keyword lists.
enum DraftDetector {
    struct Score {
        let value: Double  // 0.0–1.0
        let isDraft: Bool
    }

    private static let threshold: Double = 0.5

    static func score(_ text: String) -> Score {
        let words = text.split(whereSeparator: \.isWhitespace)
        let wordCount = words.count
        guard wordCount >= 2 else { return Score(value: 0, isDraft: false) }

        // Signal 1: word count — rough notes are short (weight 0.35)
        let lengthSignal = 1.0 - min(Double(wordCount) / 25.0, 1.0)

        // Signal 2: no sentence-ending punctuation — fragments (weight 0.35)
        let terminators = text.unicodeScalars.filter { "!.?".unicodeScalars.contains($0) }.count
        let punctSignal = 1.0 - min(Double(terminators) / max(Double(wordCount) * 0.08, 1.0), 1.0)

        // Signal 3: avg words per "sentence" < 4 — keyword/fragment style (weight 0.30)
        let chunks = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let avgWordsPerChunk: Double = chunks.isEmpty
            ? Double(wordCount)
            : Double(wordCount) / Double(chunks.count)
        let fragmentSignal = avgWordsPerChunk < 4
            ? 1.0
            : max(0.0, 1.0 - (avgWordsPerChunk - 4.0) / 8.0)

        let value = lengthSignal * 0.35 + punctSignal * 0.35 + fragmentSignal * 0.30
        return Score(value: value, isDraft: value >= threshold)
    }
}
