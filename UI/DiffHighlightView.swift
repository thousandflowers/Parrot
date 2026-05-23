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
        let maxWords = 300
        let origWords = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let corrWords = corrected.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        let truncatedOrig: [String]
        let truncatedCorr: [String]
        let wasTruncated: Bool
        if origWords.count > maxWords || corrWords.count > maxWords {
            truncatedOrig = Array(origWords.prefix(maxWords))
            truncatedCorr = Array(corrWords.prefix(maxWords))
            wasTruncated = true
        } else {
            truncatedOrig = origWords
            truncatedCorr = corrWords
            wasTruncated = false
        }

        var result = AttributedString()
        var hasChanges = false

        let lcs = longestCommonSubsequence(truncatedOrig, truncatedCorr)
        var oi = 0, ci = 0, li = 0

        while oi < truncatedOrig.count || ci < truncatedCorr.count {
            if li < lcs.count {
                while oi < truncatedOrig.count && li < lcs.count && truncatedOrig[oi] != lcs[li] {
                    let rem = truncatedOrig[oi]
                    var attr = AttributedString(rem + " ")
                    attr.foregroundColor = NSColor.systemRed
                    attr.strikethroughStyle = .single
                    attr.strikethroughColor = NSColor.systemRed
                    result.append(attr)
                    oi += 1
                    hasChanges = true
                }
                while ci < truncatedCorr.count && li < lcs.count && truncatedCorr[ci] != lcs[li] {
                    let add = truncatedCorr[ci]
                    var attr = AttributedString(add + " ")
                    attr.foregroundColor = NSColor.systemGreen
                    attr.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15)
                    result.append(attr)
                    ci += 1
                    hasChanges = true
                }
                if li < lcs.count {
                    var attr = AttributedString(lcs[li] + " ")
                    attr.foregroundColor = .primary
                    result.append(attr)
                    oi += 1
                    ci += 1
                    li += 1
                }
            } else {
                while oi < truncatedOrig.count {
                    var attr = AttributedString(truncatedOrig[oi] + " ")
                    attr.foregroundColor = NSColor.systemRed
                    attr.strikethroughStyle = .single
                    attr.strikethroughColor = NSColor.systemRed
                    result.append(attr)
                    oi += 1
                    hasChanges = true
                }
                while ci < truncatedCorr.count {
                    var attr = AttributedString(truncatedCorr[ci] + " ")
                    attr.foregroundColor = NSColor.systemGreen
                    attr.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15)
                    result.append(attr)
                    ci += 1
                    hasChanges = true
                }
            }
        }

        if wasTruncated {
            var attr = AttributedString("…")
            attr.foregroundColor = NSColor.tertiaryLabelColor
            result.append(attr)
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
