import Foundation

/// Extra sampling knobs. These are llama.cpp server extensions (and ignored/unsupported
/// by strict OpenAI endpoints), so they are encoded ONLY when non-nil. Remote services
/// leave them nil; the local llama-server path fills them in to tame small-model output
/// (repetition loops, low-probability token hallucinations).
struct SamplingParams: Sendable, Equatable {
    var topP: Double?
    var topK: Int?
    var minP: Double?
    var repeatPenalty: Double?
    var seed: Int?
}

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool

    // Optional llama.cpp sampling extensions — omitted from JSON when nil.
    var top_p: Double?
    var top_k: Int?
    var min_p: Double?
    var repeat_penalty: Double?
    var seed: Int?

    init(model: String, messages: [ChatMessage], temperature: Double, max_tokens: Int,
         stream: Bool, sampling: SamplingParams? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.stream = stream
        self.top_p = sampling?.topP
        self.top_k = sampling?.topK
        self.min_p = sampling?.minP
        self.repeat_penalty = sampling?.repeatPenalty
        self.seed = sampling?.seed
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, max_tokens, stream
        case top_p, top_k, min_p, repeat_penalty, seed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(messages, forKey: .messages)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(max_tokens, forKey: .max_tokens)
        try c.encode(stream, forKey: .stream)
        try c.encodeIfPresent(top_p, forKey: .top_p)
        try c.encodeIfPresent(top_k, forKey: .top_k)
        try c.encodeIfPresent(min_p, forKey: .min_p)
        try c.encodeIfPresent(repeat_penalty, forKey: .repeat_penalty)
        try c.encodeIfPresent(seed, forKey: .seed)
    }
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }
}
