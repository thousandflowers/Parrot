import Foundation

/// In-RAM memory of the last screen context seen in each app, so a topic follows the user
/// across app switches: read an email in Mail, switch to Slack, and the completion already
/// knows what "as I mentioned in my email" refers to.
///
/// PRIVACY: deliberately never persisted — this is OCR'd screen text. It lives only in the
/// running process and expires after `ttl`.
struct CrossAppContextStore {
    struct Entry: Equatable {
        let text: String
        let bundleID: String
        let at: Date
    }

    let ttl: TimeInterval
    let maxChars: Int
    private var entries: [String: Entry] = [:]

    init(ttl: TimeInterval = 600, maxChars: Int = 600) {
        self.ttl = ttl
        self.maxChars = maxChars
    }

    mutating func record(text: String, bundleID: String, at: Date = .now) {
        guard !text.isEmpty, !bundleID.isEmpty else { return }
        entries[bundleID] = Entry(text: String(text.suffix(maxChars)), bundleID: bundleID, at: at)
    }

    /// Most recent entry from a DIFFERENT app that is still fresh, or nil.
    func previous(excluding bundleID: String, now: Date = .now) -> Entry? {
        entries.values
            .filter { $0.bundleID != bundleID && now.timeIntervalSince($0.at) <= ttl }
            .max(by: { $0.at < $1.at })
    }
}
