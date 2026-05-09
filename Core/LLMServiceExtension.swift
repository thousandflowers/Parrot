import Foundation
import os

extension LLMService {
    func parseResponse(data: Data) throws -> String {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
            }
            json = parsed
        } catch is CorrectionError {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        } catch {
            throw CorrectionError.outputParsingFailed(raw: error.localizedDescription)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CorrectionError.outputParsingFailed(raw: String(data: data, encoding: .utf8) ?? "nil")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func buildLLMRequest(url: URL, apiKey: String?, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Constants.requestTimeout
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func performOpenAIRequest(
        body: [String: Any],
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) async throws -> String {
        try throwIfInvalidLLMURL(url)
        var request = try buildLLMRequest(url: url, apiKey: apiKey, body: body)
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var lastError: Error?
        for attempt in 0..<Constants.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CorrectionError.networkUnavailable
                }
                try handleOpenAIHTTPStatus(httpResponse.statusCode, data: data)
                return try parseResponse(data: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CorrectionError {
                switch error {
                case .invalidAPIKey, .rateLimited, .outputParsingFailed:
                    throw error
                default:
                    lastError = error
                }
            } catch let error as URLError {
                lastError = mapURLError(error)
            } catch {
                lastError = error
            }
            guard attempt < Constants.maxRetries - 1 else { break }
            let delayMs = UInt64(min(2000, 250 * Int(pow(2.0, Double(attempt)))))
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        throw lastError ?? CorrectionError.networkUnavailable
    }

    private func throwIfInvalidLLMURL(_ url: URL) throws {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw CorrectionError.networkUnavailable
        }
    }

    func mapURLError(_ error: URLError) -> CorrectionError {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost:
            return .serverNotRunning
        case .timedOut:
            return .serverTimeout
        case .notConnectedToInternet:
            return .networkUnavailable
        default:
            return .networkUnavailable
        }
    }

    func handleOpenAIHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200: return
        case 500, 502, 503: throw CorrectionError.serverTimeout
        default: throw CorrectionError.outputParsingFailed(raw: "HTTP \(statusCode)")
        }
    }

    func chatBody(model: String, prompt: String,
                  systemPrompt: String? = "You are a helpful writing assistant. Follow the user instructions exactly.",
                  temperature: Double, maxTokens: Int = 1024, stream: Bool = false) -> [String: Any] {
        var messages: [[String: String]]
        if let sys = systemPrompt {
            messages = [["role": "system", "content": sys], ["role": "user", "content": prompt]]
        } else {
            messages = [["role": "user", "content": prompt]]
        }
        return ["model": model, "messages": messages, "temperature": temperature,
                "max_tokens": maxTokens, "stream": stream]
    }

    func performOpenAIStreamRequest(
        body: [String: Any],
        url: URL,
        apiKey: String?,
        extraHeaders: [String: String] = [:]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var streamBody = body
                    streamBody["stream"] = true
                    var request = try buildLLMRequest(url: url, apiKey: apiKey, body: streamBody)
                    for (key, value) in extraHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw CorrectionError.networkUnavailable
                    }
                    try handleOpenAIHTTPStatus(httpResponse.statusCode, data: Data())

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        guard let jsonData = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            if !jsonStr.isEmpty && jsonStr != "[DONE]" {
                                os_log(.debug, "Stream: unparseable chunk: %{public}@", jsonStr.prefix(80) as NSString)
                            }
                            continue
                        }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
