import Foundation

struct CorrectionResult: Identifiable, Sendable, Codable {
    let id: UUID
    let originalText: String
    let correctedText: String
    let explanation: String?
    let confidence: Double?
    let diffOperations: [DiffOp]?
    let timestamp: Date
    let modelID: String
    let customInstruction: String?
    let promptType: String
    let detectedTone: String?
    let source: CorrectionSource

    // These fields are intentionally excluded from Codable — they are UI-specific
    // state tied to the current correction session and should not be persisted.
    var replacementRange: CFRange? = nil
    var anchorRect: CGRect? = nil

    enum CorrectionSource: String, Codable, Sendable {
        case ruleBased = "rule_based"
        case llm = "llm"
        case hybrid = "hybrid"
    }

    enum CodingKeys: String, CodingKey {
        case id, originalText, correctedText, explanation, confidence
        case diffOperations, timestamp, modelID, customInstruction, promptType, detectedTone, source
    }

    struct DiffOp: Codable, Sendable {
        enum OpType: String, Codable {
            case insert
            case delete
        }
        let type: OpType
        let offset: Int
        let length: Int
        let replacement: String?
    }

    init(
        original: String,
        corrected: String,
        modelID: String,
        explanation: String? = nil,
        confidence: Double? = nil,
        customInstruction: String? = nil,
        promptType: String = "",
        detectedTone: String? = nil,
        source: CorrectionSource = .llm
    ) {
        self.id = UUID()
        self.originalText = original
        self.correctedText = corrected
        self.explanation = explanation
        self.confidence = confidence
        self.diffOperations = CorrectionResult.computeDiff(original: original, corrected: corrected)
        self.timestamp = Date()
        self.modelID = modelID
        self.customInstruction = customInstruction
        self.promptType = promptType
        self.detectedTone = detectedTone
        self.source = source
    }

    static func computeDiff(original: String, corrected: String) -> [DiffOp]? {
        guard original != corrected else { return nil }

        struct Token { let text: Substring; let charOffset: Int }

        func tokenize(_ s: String) -> [Token] {
            var tokens: [Token] = []
            var i = s.startIndex
            while i < s.endIndex {
                while i < s.endIndex && s[i].isWhitespace { i = s.index(after: i) }
                guard i < s.endIndex else { break }
                let start = i
                let charOffset = s.distance(from: s.startIndex, to: start)
                while i < s.endIndex && !s[i].isWhitespace { i = s.index(after: i) }
                tokens.append(Token(text: s[start..<i], charOffset: charOffset))
            }
            return tokens
        }

        let origTokens = tokenize(original)
        let corrTokens = tokenize(corrected)

        let diff = corrTokens.map(\.text).difference(from: origTokens.map(\.text))
        guard !diff.isEmpty else { return nil }

        var ops: [DiffOp] = []
        for change in diff {
            switch change {
            case .remove(let wordOffset, let word, _):
                let offset = wordOffset < origTokens.count
                    ? origTokens[wordOffset].charOffset
                    : (origTokens.last.map { $0.charOffset + $0.text.count } ?? 0)
                ops.append(DiffOp(type: .delete, offset: offset, length: word.count, replacement: nil))
            case .insert(let resultOffset, let word, _):
                let offset: Int
                if resultOffset < origTokens.count {
                    offset = origTokens[resultOffset].charOffset
                } else if let last = origTokens.last {
                    offset = last.charOffset + last.text.count
                } else {
                    offset = 0
                }
                ops.append(DiffOp(type: .insert, offset: offset, length: word.count, replacement: String(word)))
            }
        }
        return ops.isEmpty ? nil : ops
    }

    var hasChanges: Bool { originalText != correctedText }

    func toAnnotations(baseOffset: Int = 0) -> [ErrorAnnotation] {
        guard hasChanges else { return [] }

        // CJK script detection by Unicode range — works even for short strings where
        // NLLanguageRecognizer is unreliable (< 12 chars).
        let hasCJK = originalText.unicodeScalars.contains {
            ($0.value >= 0x4E00 && $0.value <= 0x9FFF) ||  // CJK Unified Ideographs
            ($0.value >= 0x3040 && $0.value <= 0x30FF) ||  // Hiragana / Katakana
            ($0.value >= 0xAC00 && $0.value <= 0xD7AF)     // Hangul
        }
        guard !hasCJK else { return [] }

        var origTokens: [(word: String, offset: Int)] = []
        var idx = originalText.startIndex
        while idx < originalText.endIndex {
            while idx < originalText.endIndex && originalText[idx].isWhitespace {
                idx = originalText.index(after: idx)
            }
            guard idx < originalText.endIndex else { break }
            let wordStart = idx
            let offset = originalText.distance(from: originalText.startIndex, to: wordStart)
            while idx < originalText.endIndex && !originalText[idx].isWhitespace {
                idx = originalText.index(after: idx)
            }
            origTokens.append((String(originalText[wordStart..<idx]), offset))
        }

        let corrWords = correctedText.split { $0.isWhitespace }.map(String.init)
        let diff = corrWords.difference(from: origTokens.map { $0.word })

        var removes: [(wordIdx: Int, word: String)] = []
        var inserts: [String] = []
        for change in diff {
            switch change {
            case .remove(let offset, let word, _): removes.append((offset, word))
            case .insert(_, let word, _):          inserts.append(word)
            }
        }

        var annotations: [ErrorAnnotation] = []
        for (i, remove) in removes.enumerated() {
            guard remove.wordIdx < origTokens.count else { continue }
            let token = origTokens[remove.wordIdx]
            let fix = i < inserts.count ? inserts[i] : ""
            annotations.append(ErrorAnnotation(
                id: UUID(),
                charRange: CFRange(location: baseOffset + token.offset, length: token.word.count),
                originalSnippet: token.word,
                suggestedFix: fix,
                severity: fix.isEmpty ? .warning : .error
            ))
        }
        return annotations
    }
}
