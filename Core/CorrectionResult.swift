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

    @_documentation(visibility: internal)
    var replacementRange: CFRange? = nil

    enum CodingKeys: String, CodingKey {
        case id, originalText, correctedText, explanation, confidence
        case diffOperations, timestamp, modelID, customInstruction, promptType, detectedTone
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
        detectedTone: String? = nil
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
}
