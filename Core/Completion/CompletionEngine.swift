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
    func suggest(context: CompletionContext, maxWords: Int, allowCode: Bool = false, midWord: Bool = false) async -> CompletionSuggestion? {
        guard context.isUsable else { return nil }
        generation &+= 1
        let mine = generation

        for attempt in 0..<2 {
            var attemptCtx = context
            attemptCtx.generationSeed = UInt32(attempt)   // 0 first, 1 on retry → different sampling
            let raw: String
            do { raw = try await provider.complete(context: attemptCtx, maxWords: maxWords) }
            catch is CancellationError { return nil }
            catch {
                Logger.infra.debug("CompletionEngine: provider failed — \(error.localizedDescription, privacy: .public)")
                return nil
            }

            #if DEBUG
            CrashLogger.log("DIAG engine: raw='\(raw.replacingOccurrences(of: "\n", with: "\\n").prefix(50))' len=\(raw.count) superseded=\(mine != generation)")
            #endif

            guard mine == generation else { return nil }
            if let cleaned = CompletionPostprocessor.clean(raw: raw, preContext: context.preContext,
                                                           maxWords: maxWords, allowCode: allowCode, midWord: midWord),
               !cleaned.isEmpty {
                return CompletionSuggestion(text: cleaned)
            }
            #if DEBUG
            CrashLogger.log("DIAG engine: clean→nil for raw='\(raw.replacingOccurrences(of: "\n", with: "\\n").prefix(50))'")
            #endif
            if attempt == 0 { continue }   // one retry, then give up
        }
        return nil
    }

    /// Invalidates any in-flight suggestion so its result is discarded when it returns.
    func cancelPending() {
        generation &+= 1
    }

    /// Loads the model into RAM ahead of typing by issuing one throwaway completion. Without this,
    /// the first real keystroke triggers a multi-second cold load while every following keystroke
    /// supersedes the in-flight request, so nothing ever completes until the user pauses for ~10s.
    func warmup() async {
        let ctx = CompletionContext(preContext: "The", postContext: "", language: "en")
        _ = try? await provider.complete(context: ctx, maxWords: 2)
    }
}
