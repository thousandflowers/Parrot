import Foundation
import OSLog

/// Produces inline completion suggestions. Serialises requests and supersedes stale ones:
/// when a newer `suggest` starts, any in-flight older result is discarded (returns nil), so a
/// late completion for text the user has already moved past never appears.
actor CompletionEngine {
    // In-process helper for dedicated completion models (warm KV reuse); falls back to the
    // server-based client when no dedicated model is configured or RAM is tight.
    static let shared = CompletionEngine(provider: HelperCompletionProvider())

    private let provider: CompletionProviding
    private var generation: UInt64 = 0

    init(provider: CompletionProviding) {
        self.provider = provider
    }

    /// Returns a cleaned suggestion for the context, or nil if there is nothing to show
    /// (unusable context, empty/echo result, an error, or the request was superseded).
    func suggest(context: CompletionContext, maxWords: Int, allowCode: Bool = false) async -> CompletionSuggestion? {
        guard context.isUsable else { return nil }
        generation &+= 1
        let mine = generation

        let raw: String
        do {
            raw = try await provider.complete(context: context, maxWords: maxWords)
        } catch is CancellationError {
            return nil
        } catch {
            Logger.infra.debug("CompletionEngine: provider failed — \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Superseded by a newer request while we were waiting → drop.
        guard mine == generation else { return nil }

        guard let cleaned = CompletionPostprocessor.clean(raw: raw, preContext: context.preContext, maxWords: maxWords, allowCode: allowCode),
              !cleaned.isEmpty else {
            return nil
        }
        return CompletionSuggestion(text: cleaned)
    }

    /// Invalidates any in-flight suggestion so its result is discarded when it returns.
    func cancelPending() {
        generation &+= 1
    }
}
