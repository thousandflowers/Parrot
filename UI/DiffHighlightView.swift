import SwiftUI

struct DiffHighlightView: View, Equatable {
    let original: String
    let corrected: String

    var body: some View {
        let diff = computeDiff()
        HStack(spacing: 0) {
            Text(diff.attributed)
        }
    }

    private func computeDiff() -> (attributed: AttributedString, hasChanges: Bool) {
        let origWords = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let corrWords = corrected.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        var result = AttributedString()
        var hasChanges = false

        // Simple greedy word-level diff: align by longest common subsequence
        let lcs = longestCommonSubsequence(origWords, corrWords)
        var oi = 0, ci = 0, li = 0

        while oi < origWords.count || ci < corrWords.count {
            if li < lcs.count {
                // Emit deletions from original before next LCS match
                while oi < origWords.count && li < lcs.count && origWords[oi] != lcs[li] {
                    let rem = origWords[oi]
                    var attr = AttributedString(rem + " ")
                    attr.foregroundColor = NSColor.refineError
                    attr.strikethroughStyle = .single
                    attr.strikethroughColor = NSColor.refineError
                    result.append(attr)
                    oi += 1
                    hasChanges = true
                }
                // Emit insertions from corrected before next LCS match
                while ci < corrWords.count && li < lcs.count && corrWords[ci] != lcs[li] {
                    let add = corrWords[ci]
                    var attr = AttributedString(add + " ")
                    attr.foregroundColor = NSColor.refineSuccess
                    attr.backgroundColor = NSColor.refineSuccess.withAlphaComponent(0.15)
                    result.append(attr)
                    ci += 1
                    hasChanges = true
                }
                // Emit common word
                if li < lcs.count {
                    var attr = AttributedString(lcs[li] + " ")
                    attr.foregroundColor = .primary
                    result.append(attr)
                    oi += 1
                    ci += 1
                    li += 1
                }
            } else {
                // Remaining original words (deletions beyond LCS)
                while oi < origWords.count {
                    var attr = AttributedString(origWords[oi] + " ")
                    attr.foregroundColor = NSColor.refineError
                    attr.strikethroughStyle = .single
                    attr.strikethroughColor = NSColor.refineError
                    result.append(attr)
                    oi += 1
                    hasChanges = true
                }
                // Remaining corrected words (insertions beyond LCS)
                while ci < corrWords.count {
                    var attr = AttributedString(corrWords[ci] + " ")
                    attr.foregroundColor = NSColor.refineSuccess
                    attr.backgroundColor = NSColor.refineSuccess.withAlphaComponent(0.15)
                    result.append(attr)
                    ci += 1
                    hasChanges = true
                }
            }
        }

        return (result, hasChanges)
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1] + 1 : max(dp[i-1][j], dp[i][j-1])
            }
        }
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                result.append(a[i-1])
                i -= 1; j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }
}
