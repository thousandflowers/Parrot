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

    @_documentation(visibility: internal)
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
        replacementRange: CFRange? = nil,
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
        self.replacementRange = replacementRange
        self.detectedTone = detectedTone
        self.source = source
    }

    static func computeDiff(original: String, corrected: String) -> [DiffOp]? {
        guard original != corrected else { return nil }

        let origWords = original.split(separator: " ", omittingEmptySubsequences: true)
        let corrWords = corrected.split(separator: " ", omittingEmptySubsequences: true)

        let diff = corrWords.difference(from: origWords)
        guard !diff.isEmpty else { return nil }

        var charOffsets: [Int] = []
        var scanner = original.startIndex
        for word in origWords {
            charOffsets.append(original.distance(from: original.startIndex, to: scanner))
            let wordEnd = original.index(scanner, offsetBy: word.count, limitedBy: original.endIndex) ?? original.endIndex
            scanner = wordEnd < original.endIndex ? original.index(after: wordEnd) : original.endIndex
        }

        var ops: [DiffOp] = []
        var origIdx = 0

        for change in diff {
            switch change {
            case .remove(let wordOffset, let word, _):
                while origIdx < wordOffset && origIdx < charOffsets.count {
                    origIdx += 1
                }
                let charOffset = origIdx < charOffsets.count ? charOffsets[origIdx] : charOffsets.last ?? 0
                ops.append(DiffOp(type: .delete, offset: charOffset, length: word.count, replacement: nil))
                origIdx += 1
            case .insert(_, let word, _):
                let charOffset = origIdx < charOffsets.count ? charOffsets[origIdx] : charOffsets.last ?? 0
                ops.append(DiffOp(type: .insert, offset: charOffset, length: word.count, replacement: String(word)))
            }
        }

        return ops.isEmpty ? nil : ops
    }

    var hasChanges: Bool { originalText != correctedText }

    func toAnnotations(baseOffset: Int = 0) -> [ErrorAnnotation] {
        guard hasChanges else { return [] }

        // Tokenize original text, preserving char offsets
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
