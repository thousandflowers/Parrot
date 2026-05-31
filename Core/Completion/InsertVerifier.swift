/// Decides whether an AX insert silently failed and a one-shot keystroke fallback is needed.
/// Never loops: at most one retry, only when we can positively read that the text is missing.
enum InsertVerifier {
    static func needsKeystrokeFallback(expectedInsert: String, before: String, after: String?) -> Bool {
        guard let after else { return false }          // can't read → don't risk double insert
        if after == before { return true }             // nothing changed → AX insert failed
        return !after.contains(expectedInsert)         // changed but our text isn't there
    }
}
