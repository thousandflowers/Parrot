import Foundation

/// Pure cleaning of a raw model continuation into a short inline suggestion.
/// No I/O, no state — fully unit-testable.
enum CompletionPostprocessor {
    /// Cleans `raw` into an inline suggestion, or returns nil if there is nothing useful to show.
    /// - `preContext`: the text before the caret, used to strip an echoed prefix.
    /// - `maxWords`: hard cap on suggestion length (a "short" completion budget).
    /// - `midWord`: the caret sits inside a partial word (e.g. "rece"). The suggestion then CONTINUES
    ///   that word with no boundary space ("ption" → "reception"). When false, a word boundary is
    ///   assumed and exactly one space separates the prior word from the suggestion.
    static func clean(raw: String, preContext: String, maxWords: Int, allowCode: Bool = false, midWord: Bool = false) -> String? {
        var text = raw

        // 0a. Reject LEADING AI preamble / instruction-leak only. Anchored to the start: a substring
        //     match was rejecting valid completions ("...let me know", "...here's the plan"). Real
        //     preamble appears at the front ("Sure! ...", "You are ...").
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        let metaPrefixes = ["you are", "as an ai", "output only", "continue the text",
                            "completion that directly", "sure!", "certainly!", "of course!",
                            "i'd be happy", "here is the completion"]
        if metaPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }

        // 0. In plain-text fields, base (web-pretrained) models sometimes drift into HTML/markdown/
        //    code. Strip inline markup and reject code-looking output. SKIPPED in code editors, where
        //    code/markup is exactly what the user wants.
        // Reject only an UNWANTED script switch: if the context is Latin and the suggestion is
        // (mostly) CJK, drop it; if the user writes CJK, CJK is fine. Granular, supports all users.
        if isCJKDominant(text) && !isCJKDominant(preContext) { return nil }

        if !allowCode {
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "`", with: "")
            // Web-pretrained base models emit escaped sequences (\" \\ ) from JSON/code training data,
            // showing as "2018\\ \", ma una". Backslashes are virtually never wanted in prose → drop.
            text = text.replacingOccurrences(of: "\\", with: "")
            // Stray underscores ("_", "___") are a model artifact, never wanted in prose → drop.
            text = text.replacingOccurrences(of: "_", with: "")
            // Strip a LEADING list/enumeration marker ("1)", "2.", "- ", "• ") — the model sometimes
            // slips into a numbered/bulleted list or internal reasoning ("1) First, …") instead of
            // continuing the sentence. After stripping, a bare " 1)" leaves nothing → rejected below.
            text = text.replacingOccurrences(of: "^\\s*(\\d{1,4}[.):]|[-•*])\\s*", with: "",
                                             options: .regularExpression)
            // Only reject keywords in code-definition form (e.g. "function foo()")
            // — standalone "function" or "import" in plain English is valid text.
            if text.range(of: "[<>{}]|/>|</|=>|;\\s*$|\\bfunction\\s+\\w+\\s*\\(|\\bconst\\s+\\w+\\s*=|\\bdef\\s+\\w+\\s*\\(|\\bimport\\s+\\w+",
                          options: .regularExpression) != nil {
                return nil
            }
        }

        // 1. Strip a restated overlap: models sometimes re-enunciate the user's text (optionally with
        //    a small inserted leading word like "il") before the real continuation.
        text = stripRestatedOverlap(suggestion: text, preContext: preContext)

        // 2. Short completions stop at the first line break — a new paragraph is not an inline hint.
        if let nl = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            text = String(text[..<nl])
        }

        // 3. Collapse to the word budget.
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Drop a leading word that merely repeats the last word the user already typed — the model
        // sometimes echoes it ("…molto" → " molto bene" would render as "molto molto bene"). Only at
        // a word boundary; mid-word, continuing the same token is correct.
        if !midWord, !words.isEmpty {
            let lastTyped = preContext.split(whereSeparator: { $0 == " " || $0.isNewline || $0 == "\t" }).last.map(String.init) ?? ""
            if !lastTyped.isEmpty, words[0].lowercased() == lastTyped.lowercased() {
                words.removeFirst()
            }
        }
        // 3b. Collapse internal repetitions so the model's looping reads as a clean sentence instead
        //     of being thrown away (#2 "frasi con ripetizioni"): drop immediate duplicate words
        //     ("the the" → "the") and a whole-phrase doubling ("I think I think" → "I think").
        var deduped: [String] = []
        for w in words where deduped.last?.lowercased() != w.lowercased() { deduped.append(w) }
        words = deduped
        if words.count >= 4, words.count % 2 == 0 {
            let half = words.count / 2
            if words.prefix(half).map({ $0.lowercased() }) == words.suffix(half).map({ $0.lowercased() }) {
                words = Array(words.prefix(half))
            }
        }
        guard !words.isEmpty else { return nil }
        var capped = words.prefix(max(1, maxWords)).joined(separator: " ")

        // 4. Join spacing (the model is unreliable at the boundary space, so decide it here):
        //    - mid-word → CONTINUE the token, no space, even if the model emitted one ("rece"→"ption");
        //    - word boundary after a non-space char → exactly one leading space;
        //    - empty preContext or already ends with whitespace → no leading space (never double).
        let lead = String(capped.drop(while: { $0.isWhitespace }))   // strip leading space OR tab (model echoes "\t")
        if midWord {
            capped = lead                                       // continue the token, no space ("rece"+" ption"→"ption")
        } else if let last = preContext.last, !last.isWhitespace {
            capped = " " + lead                                 // boundary after a word → exactly one space
        } else {
            capped = lead                                       // empty preContext, or already ends with space → none
        }
        text = capped

        // 5. A pure-whitespace result is useless.
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }

        // 6. Loop guard: small models sometimes echo text the user just wrote. If the suggestion
        //    (trimmed) already appears at the tail of the recent context, it's a repetition — drop it.
        let suggestionCore = text.trimmingCharacters(in: .whitespaces).lowercased()
        if suggestionCore.count >= 4 {
            let tail = String(preContext.suffix(160)).lowercased()
            if tail.contains(suggestionCore) { return nil }
        }

        // 7. Reject output with no letters at all — e.g. "100000000000", "．____". Small models emit
        //    digit/punctuation runs (especially for non-English input); a letter-less run is never a
        //    useful word completion.
        if !text.contains(where: { $0.isLetter }) { return nil }

        return text
    }

    private static func isCJKDominant(_ s: String) -> Bool {
        func isCJK(_ v: UInt32) -> Bool {
            (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) ||
            (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v) ||
            (0xF900...0xFAFF).contains(v)
        }
        var letters = 0, cjk = 0
        for ch in s {
            for v in ch.unicodeScalars where ch.isLetter { letters += 1; if isCJK(v.value) { cjk += 1 }; break }
        }
        guard letters > 0 else { return false }
        return Double(cjk) / Double(letters) >= 0.5
    }

    /// Removes any leading run of `suggestion` that merely restates the tail of `preContext`.
    /// Tolerates up to two inserted leading tokens in the suggestion (e.g. "il 1984 …").
    static func stripRestatedOverlap(suggestion: String, preContext: String) -> String {
        func norm(_ s: String) -> [String] {
            s.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        }
        let pre = norm(preContext)
        guard pre.count >= 2 else { return suggestion }
        let sugWords = suggestion.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let sugNorm = norm(suggestion)
        // The longest tail of preContext (≥2 words) that appears in the suggestion's first ~8 words,
        // allowing up to 2 leading filler words before the match.
        for tailLen in stride(from: min(pre.count, 12), through: 2, by: -1) {
            let tail = Array(pre.suffix(tailLen))
            for offset in 0...2 where offset + tail.count <= sugNorm.count {
                if Array(sugNorm[offset..<offset + tail.count]) == tail {
                    // Cut the suggestion's real words up to and including this overlap.
                    let cutWordCount = offset + tail.count
                    let kept = sugWords.drop(while: { $0.isEmpty }).dropFirst(cutWordCount)
                    return kept.joined(separator: " ")
                }
            }
        }
        return suggestion
    }
}
