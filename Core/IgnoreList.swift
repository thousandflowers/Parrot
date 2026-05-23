import Foundation

struct IgnoreList {
    private static let key = "ignoredWords"

    static func isIgnored(_ word: String) -> Bool {
        ignoredWords().contains(word.lowercased())
    }

    static func ignore(_ word: String) {
        var words = ignoredWords()
        let lower = word.lowercased()
        guard !words.contains(lower) else { return }
        words.append(lower)
        UserDefaults.standard.set(words, forKey: key)
    }

    static func remove(_ word: String) {
        var words = ignoredWords()
        words.removeAll { $0 == word.lowercased() }
        UserDefaults.standard.set(words, forKey: key)
    }

    static func all() -> [String] {
        ignoredWords()
    }

    private static func ignoredWords() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
