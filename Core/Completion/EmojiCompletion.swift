import Foundation

/// Emoji completion: typing a `:shortcode` (Slack/GitHub style) suggests the emoji; Tab replaces
/// `:shortcode` with it. The map is reference data (a lookup table), not behavioral branching.
enum EmojiCompletion {
    struct Match: Equatable { let shortcode: String; let emoji: String }

    /// If the caret follows a `:word` shortcode that maps to an emoji, returns the match.
    static func match(preContext: String) -> Match? {
        // Trailing ":" + word chars.
        let trailing = preContext.reversed().prefix { $0.isLetter || $0 == "_" }
        let word = String(trailing.reversed())
        guard word.count >= 2 else { return nil }
        let idx = preContext.index(preContext.endIndex, offsetBy: -word.count)
        guard idx > preContext.startIndex, preContext[preContext.index(before: idx)] == ":" else { return nil }
        guard let emoji = table[word.lowercased()] else { return nil }
        return Match(shortcode: ":\(word)", emoji: emoji)
    }

    /// Common shortcodes. Reference data; extend freely. (Skin-tone variants left for a later pass.)
    private static let table: [String: String] = [
        "smile": "😄", "grin": "😁", "joy": "😂", "rofl": "🤣", "wink": "😉", "blush": "😊",
        "heart": "❤️", "hearts": "💕", "broken_heart": "💔", "fire": "🔥", "star": "⭐️",
        "sparkles": "✨", "tada": "🎉", "party": "🥳", "clap": "👏", "thumbsup": "👍", "+1": "👍",
        "thumbsdown": "👎", "-1": "👎", "ok": "👌", "ok_hand": "👌", "wave": "👋", "pray": "🙏",
        "muscle": "💪", "eyes": "👀", "rocket": "🚀", "100": "💯", "check": "✅",
        "white_check_mark": "✅", "x": "❌", "warning": "⚠️", "bulb": "💡", "bell": "🔔",
        "thinking": "🤔", "sob": "😭", "cry": "😢", "sweat_smile": "😅", "facepalm": "🤦",
        "shrug": "🤷", "cool": "😎", "sunglasses": "😎", "love": "😍", "kiss": "😘",
        "wink_heart": "😘", "angry": "😠", "rage": "😡", "sad": "😞", "neutral": "😐",
        "sleeping": "😴", "poop": "💩", "ghost": "👻", "skull": "💀", "alien": "👽",
        "robot": "🤖", "cat": "🐱", "dog": "🐶", "unicorn": "🦄", "parrot": "🦜", "bird": "🐦",
        "coffee": "☕️", "beer": "🍺", "pizza": "🍕", "cake": "🎂", "gift": "🎁",
        "sun": "☀️", "moon": "🌙", "rainbow": "🌈", "snow": "❄️", "zap": "⚡️",
        "ok_emoji": "🆗", "new": "🆕", "up": "⬆️", "down": "⬇️", "left": "⬅️", "right": "➡️",
        "phone": "📱", "computer": "💻", "email": "📧", "lock": "🔒", "key": "🔑",
        "money": "💰", "chart": "📈", "calendar": "📅", "clock": "⏰", "hourglass": "⏳",
    ]
}
