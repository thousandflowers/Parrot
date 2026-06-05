import Foundation

/// Text around the caret used to request an inline completion.
struct CompletionContext: Sendable, Equatable {
    /// Text immediately before the caret (the prefix the model continues).
    let preContext: String
    /// Text immediately after the caret. May be empty (end-of-text, the common case).
    let postContext: String
    let language: String
    /// If set, overrides the default completion user prompt (e.g. per-app rules).
    var userPromptOverride: String? = nil
    /// Personalization instructions (steers model toward the user's voice). Empty = use fallback.
    var personalizationInstructions: String = ""
    /// How strongly personalization affects the completion (0.0 = coldest, 1.0 = default temp).
    var personalizationStrength: Double = 0.5
    /// The selected model ID for completion (empty = use the same model as correction).
    var completionModelID: String = ""
    /// The selected model ID for correction (used to check if a dedicated completion model is configured).
    var selectedModelID: String = ""
    /// Style-profile descriptor injected into the model prompt (fingerprint of user's writing).
    var styleDescriptor: String = ""
    /// Per-attempt generation seed. 0 on the first attempt; bumped on a retry so the sampler draws
    /// a different token sequence (otherwise near-deterministic models return the same empty output).
    var generationSeed: UInt32 = 0

    var isUsable: Bool {
        preContext.trimmingCharacters(in: .whitespacesAndNewlines).count >= Constants.completionMinPrefixChars
    }
}

/// Whether accepting a suggestion inserts text at the caret or replaces the mistyped last word.
enum SuggestionKind: Sendable, Equatable {
    case insert
    case replaceLastWord(wrong: String)
}

/// A cleaned completion suggestion ready to display as ghost text and insert on accept.
struct CompletionSuggestion: Sendable, Equatable {
    /// What gets inserted on a full (Tab) accept (or the replacement word for a typo fix).
    let text: String
    var kind: SuggestionKind = .insert

    /// First whitespace-delimited word, for partial accept. Includes the trailing space if present
    /// so repeated partial-accepts read naturally.
    var firstWord: String {
        guard let firstNonSpace = text.firstIndex(where: { !$0.isWhitespace }) else { return text }
        let leading = text[..<firstNonSpace]
        let rest = text[firstNonSpace...]
        guard let wordEnd = rest.firstIndex(where: { $0.isWhitespace }) else { return text }
        // include one trailing space so the next suggestion starts cleanly
        let afterWord = rest[wordEnd...]
        let spaceEnd = afterWord.firstIndex(where: { !$0.isWhitespace }) ?? afterWord.endIndex
        return String(leading) + String(rest[..<wordEnd]) + String(afterWord[..<spaceEnd])
    }
}

/// Snapshot of the focused text field read for an inline completion.
/// `caretRect` is in screen coordinates with a TOP-LEFT origin (as `boundsForRange` returns).
struct CompletionAXContext: Sendable, Equatable {
    let preContext: String
    let postContext: String
    let caretRect: CGRect
    let isSecure: Bool
    var fontName: String? = nil
    var fontSize: CGFloat = 0
}

/// Abstraction over the inference backend so `CompletionEngine` is testable without a live server.
protocol CompletionProviding: Sendable {
    /// Returns the raw model continuation for the given context (uncleaned), or throws on failure.
    func complete(context: CompletionContext, maxWords: Int) async throws -> String
}
