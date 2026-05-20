import Foundation
import OSLog

/// Dedicated SSE (Server-Sent Events) streaming engine.
/// Parses OpenAI-compatible streaming responses and yields accumulated text.
/// Completely agnostic to the service — only needs a URLRequest.
actor SSEStreamingEngine {
    static let shared = SSEStreamingEngine()

    /// Shared ephemeral session — avoids allocating a new session per request.
    /// Cancellation is handled at Task level; the session is never invalidated.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Constants.requestTimeout
        return URLSession(configuration: config)
    }()

    /// Streams text from an OpenAI-compatible SSE endpoint.
    /// Yields the **accumulated** text after each chunk (not just the delta).
    /// Retries once on transient network errors; never retries auth/rate/parsing errors.
    /// - Parameter request: Pre-configured URLRequest with streaming body.
    /// - Returns: AsyncThrowingStream of accumulated text strings.
    func stream(request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error?
                for attempt in 0..<2 {
                    do {
                        try await self.attemptStream(request: request, continuation: continuation)
                        return  // success — stream finished normally
                    } catch is CancellationError {
                        return  // never retry cancellations
                    } catch let error as CorrectionError {
                        switch error {
                        case .invalidAPIKey, .rateLimited, .modelNotLoaded, .outputParsingFailed:
                            continuation.finish(throwing: error)
                            return
                        default:
                            lastError = error
                        }
                    } catch {
                        lastError = error
                    }

                    if attempt == 0 {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
                guard !Task.isCancelled else { return }
                continuation.finish(throwing: lastError ?? CorrectionError.networkUnavailable)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func attemptStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionError.networkUnavailable
        }
        try throwIfHTTPError(httpResponse)

        var accumulated = ""
        var skippedChunks = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }
            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                if !jsonStr.isEmpty && jsonStr != "[DONE]" {
                    skippedChunks += 1
                    if skippedChunks <= 3 {
                        Logger.core.debug("SSE: unparseable chunk (\(skippedChunks, privacy: .public))")
                    }
                }
                continue
            }
            accumulated += content
            continuation.yield(accumulated)
        }
        if accumulated.isEmpty {
            throw CorrectionError.outputParsingFailed(raw: "empty")
        }
        continuation.finish()
    }

    private func throwIfHTTPError(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 401, 403: throw CorrectionError.invalidAPIKey
        case 429: throw CorrectionError.rateLimited
        case 404: throw CorrectionError.modelNotLoaded
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(response.statusCode)")
        }
    }
}
