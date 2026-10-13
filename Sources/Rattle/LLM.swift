import Foundation

enum LLMError: LocalizedError {
    case unreachable(String)
    case noModel
    case server(String)
    var errorDescription: String? {
        switch self {
        case .unreachable(let url): return "AI server not reachable at \(url). Start LM Studio's server (lms server start) or change it in Settings → AI."
        case .noModel: return "No AI model is loaded on the server. Load one in LM Studio or pick a model in Settings → AI."
        case .server(let m): return m
        }
    }
}

/// Minimal client for any OpenAI-compatible /chat/completions endpoint (LM Studio, Ollama, OpenAI, ...).
enum LLM {
    struct Config {
        var baseURL: String
        var model: String
        var key: String
        init(_ s: Settings) { baseURL = s.llmBaseURL; model = s.llmModel; key = s.llmKey }
        var root: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }
    }

    private static func request(_ c: Config, path: String, body: Data? = nil, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: c.root + path) else { throw LLMError.unreachable(c.baseURL) }
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        if !c.key.isEmpty { r.setValue("Bearer \(c.key)", forHTTPHeaderField: "Authorization") }
        if let body { r.httpMethod = "POST"; r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    static func models(_ c: Config) async throws -> [String] {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(c, path: "/models", timeout: 4))
            let status = (resp as? HTTPURLResponse)?.statusCode
            if status == 401 || status == 403 { throw LLMError.server(c.key.isEmpty ? "This service needs an API key" : "The API key was rejected") }
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else { throw LLMError.server("Unexpected response from the AI server") }
            return arr.compactMap { $0["id"] as? String }.filter { !$0.lowercased().contains("embed") }
        } catch let e as LLMError { throw e }
        catch { throw LLMError.unreachable(c.baseURL) }
    }

    static func chat(system: String, user: String, settings: Settings, maxTokens: Int = 1200, timeout: TimeInterval = 90) async throws -> String {
        var c = Config(settings)
        if c.model.isEmpty {
            guard let first = try await models(c).first else { throw LLMError.noModel }
            c.model = first
        }
        let payload: [String: Any] = [
            "model": c.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0.3,
            "max_tokens": maxTokens + 1024,   // headroom for models that think before answering
            "stream": false
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: request(c, path: "/chat/completions", body: body, timeout: timeout)) }
        catch let e as URLError where e.code == .timedOut { throw LLMError.server("The AI model took too long to answer.") }
        catch { throw LLMError.unreachable(c.baseURL) }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? (json?["error"] as? String) ?? "AI server error"
            throw LLMError.server(msg)
        }
        let choice = (json?["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        let content = stripThinking((message?["content"] as? String) ?? "")
        if content.isEmpty {
            let thought = !(((message?["reasoning_content"] as? String) ?? "").isEmpty)
            throw LLMError.server(thought
                ? "The AI model used its whole budget thinking and never answered. Choose a non-reasoning (instruct) model in Settings → AI."
                : "The AI server returned an empty answer.")
        }
        return content
    }

    /// Removes <think>…</think> blocks emitted by reasoning models.
    static func stripThinking(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        if let r = t.range(of: "<think>") { t = String(t[..<r.lowerBound]) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Transforms {
    static let builtIns: [Transform] = [
        Transform(id: "polish", name: "Polish", prompt: "Rewrite the text so it reads clearly and naturally. Fix grammar, remove repetition and awkward phrasing. Keep the author's meaning, voice and language. Do not add new information.", builtIn: true),
        Transform(id: "concise", name: "Make concise", prompt: "Shorten the text as much as possible without losing any important information. Keep the author's voice.", builtIn: true),
        Transform(id: "professional", name: "Professional tone", prompt: "Rewrite the text in a clear, polite, professional tone suitable for work communication. Keep the meaning.", builtIn: true),
        Transform(id: "friendly", name: "Friendly tone", prompt: "Rewrite the text in a warm, friendly, conversational tone. Keep the meaning.", builtIn: true),
        Transform(id: "grammar", name: "Fix grammar only", prompt: "Fix spelling, grammar and punctuation only. Do not change wording or style.", builtIn: true),
        Transform(id: "bullets", name: "Bullet points", prompt: "Restructure the text into a short list of clear bullet points (each starting with \"- \"). Keep every key point.", builtIn: true),
        Transform(id: "email", name: "Format as email", prompt: "Turn the text into a well-formed email with a greeting and sign-off. Keep the meaning and do not invent facts or names.", builtIn: true),
        Transform(id: "english", name: "Translate to English", prompt: "Translate the text into natural English.", builtIn: true),
    ]

    private static let base = "You are a text transformation engine inside a dictation app. Output ONLY the resulting text: no preface, no explanation, no surrounding quotes, no markdown fences. Reply in the same language as the input unless told otherwise."

    static func run(_ t: Transform, on text: String, settings: Settings, timeout: TimeInterval = 60) async throws -> String {
        let out = try await LLM.chat(system: base + "\n\nInstruction: " + t.prompt, user: text, settings: settings, maxTokens: max(256, text.count), timeout: timeout)
        return out.isEmpty ? text : out
    }

    /// Command Mode: a spoken instruction applied to the selected text, or a draft written from scratch when nothing is selected.
    static func command(instruction: String, selection: String?, settings: Settings) async throws -> String {
        if let selection, !selection.isEmpty {
            let sys = base + "\n\nThe user selected some text and spoke an instruction describing how to change it. Apply the instruction to the selected text and return the full rewritten text."
            return try await LLM.chat(system: sys, user: "Instruction: \(instruction)\n\nSelected text:\n\(selection)", settings: settings, maxTokens: max(256, selection.count * 2))
        }
        let sys = base + "\n\nThe user spoke a request for text to be written (a reply, a message, a short passage). Write exactly that text, ready to paste."
        return try await LLM.chat(system: sys, user: instruction, settings: settings, maxTokens: 700)
    }
}
