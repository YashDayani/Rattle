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

    /// `model` overrides the AI model from settings when non-empty.
    static func chat(system: String, user: String, settings: Settings, model: String = "", maxTokens: Int = 1200, timeout: TimeInterval = 90) async throws -> String {
        var c = Config(settings)
        if !model.isEmpty { c.model = model }
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
        var data = Data(), status = 0
        // Busy or rate-limited servers (429, 503) usually recover within seconds, so retry those twice.
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000) }
            let resp: URLResponse
            do { (data, resp) = try await URLSession.shared.data(for: request(c, path: "/chat/completions", body: body, timeout: timeout)) }
            catch let e as URLError where e.code == .timedOut { throw LLMError.server("The AI model took too long to answer.") }
            catch { throw LLMError.unreachable(c.baseURL) }
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status != 429 && status != 503 { break }
        }
        let parsed = try? JSONSerialization.jsonObject(with: data)
        // Gemini wraps errors in a one-element array.
        let json = (parsed as? [String: Any]) ?? (parsed as? [[String: Any]])?.first
        guard status == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? (json?["error"] as? String) ?? "AI server error (\(status))"
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

/// Sends a meeting recording to Gemini (Files API + generateContent) so notes come from the audio itself.
enum GeminiAudio {
    private static let root = "https://generativelanguage.googleapis.com"

    static func supports(_ s: Settings) -> Bool { URL(string: s.llmBaseURL)?.host == "generativelanguage.googleapis.com" }

    static func summarize(audio: URL, system: String, prompt: String, settings s: Settings, model: String, maxTokens: Int, timeout: TimeInterval) async throws -> String {
        guard !s.llmKey.isEmpty else { throw LLMError.server("Add your Gemini API key in Settings → AI.") }
        let name = [model, s.llmModel].first { !$0.isEmpty } ?? "gemini-flash-latest"
        let modelPath = name.hasPrefix("models/") ? name : "models/" + name
        let file = try await upload(audio, key: s.llmKey)
        defer { Task { _ = try? await send(path: "/v1beta/" + file.name, method: "DELETE", key: s.llmKey, timeout: 15) } }

        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["file_data": ["mime_type": file.mime, "file_uri": file.uri]], ["text": prompt]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": maxTokens + 2048]
        ]
        var json: [String: Any] = [:]
        // Busy or rate-limited (429, 503): retry twice.
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000) }
            let (j, status) = try await send(path: "/v1beta/\(modelPath):generateContent", body: JSONSerialization.data(withJSONObject: payload), key: s.llmKey, timeout: timeout)
            json = j
            if status == 200 { break }
            if (status != 429 && status != 503) || attempt == 2 { throw LLMError.server(errorMessage(j, status)) }
        }
        let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = LLM.stripThinking(parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined())
        if text.isEmpty { throw LLMError.server("Gemini returned an empty answer for the recording.") }
        return text
    }

    /// Dictation translation: the short WAV goes inline to Gemini, which listens to it and writes what was meant in `language`.
    static func translate(wav: Data, to language: String, vocabulary: [String], settings s: Settings) async throws -> String {
        guard supports(s), !s.llmKey.isEmpty else { throw LLMError.server("Translate needs Gemini. Pick Gemini and add your key in Settings → AI.") }
        let name = [s.summaryModel, s.llmModel].first { !$0.isEmpty } ?? "gemini-flash-latest"
        let modelPath = name.hasPrefix("models/") ? name : "models/" + name
        var system = "You are the translator inside a dictation app. Listen to the audio, understand what the speaker means, and write it naturally in \(language), as the speaker would say it if they spoke \(language). Keep names, numbers and technical terms accurate. Output ONLY the resulting text: no preface, no quotes, no notes. If the audio has no speech, output nothing."
        if !vocabulary.isEmpty { system += " Spell these words exactly if they are spoken: " + vocabulary.joined(separator: ", ") + "." }
        let payload = translatePayload(wav: wav, system: system, language: language)
        var json: [String: Any] = [:]
        for attempt in 0..<3 {
            if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000) }
            let (j, status) = try await send(path: "/v1beta/\(modelPath):generateContent", body: JSONSerialization.data(withJSONObject: payload), key: s.llmKey, timeout: 60)
            json = j
            if status == 200 { break }
            if (status != 429 && status != 503) || attempt == 2 { throw LLMError.server(errorMessage(j, status)) }
        }
        return extractText(json)
    }

    static func translatePayload(wav: Data, system: String, language: String) -> [String: Any] {
        [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["inline_data": ["mime_type": "audio/wav", "data": wav.base64EncodedString()]], ["text": "Write what was said in \(language)."]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 2048 + 2048]
        ]
    }

    static func extractText(_ json: [String: Any]) -> String {
        let parts = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return LLM.stripThinking(parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined())
    }

    private struct File { let name, uri, mime: String }

    private static func upload(_ url: URL, key: String) async throws -> File {
        guard let data = try? Data(contentsOf: url) else { throw LLMError.server("Couldn't read the meeting recording.") }
        var r = URLRequest(url: URL(string: root + "/upload/v1beta/files")!)
        r.httpMethod = "POST"; r.timeoutInterval = 600
        r.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        r.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (body, resp): (Data, URLResponse)
        do { (body, resp) = try await URLSession.shared.upload(for: r, from: data) }
        catch { throw LLMError.server("Couldn't upload the recording to Gemini. Check your internet connection.") }
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, var f = json["file"] as? [String: Any] else { throw LLMError.server(errorMessage(json, status)) }
        // Large files are processed before they can be used.
        var waited = 0
        while (f["state"] as? String) == "PROCESSING", waited < 300 {
            try await Task.sleep(nanoseconds: 2_000_000_000); waited += 2
            if let name = f["name"] as? String { f = try await send(path: "/v1beta/" + name, method: "GET", key: key, timeout: 30).json }
        }
        guard (f["state"] as? String) == "ACTIVE", let name = f["name"] as? String, let uri = f["uri"] as? String else {
            throw LLMError.server("Gemini couldn't process the recording.")
        }
        return File(name: name, uri: uri, mime: (f["mimeType"] as? String) ?? "audio/mp4")
    }

    private static func send(path: String, method: String = "POST", body: Data? = nil, key: String, timeout: TimeInterval) async throws -> (json: [String: Any], status: Int) {
        var r = URLRequest(url: URL(string: root + path)!)
        r.httpMethod = method; r.timeoutInterval = timeout; r.httpBody = body
        r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: r) }
        catch let e as URLError where e.code == .timedOut { throw LLMError.server("Gemini took too long to answer.") }
        catch { throw LLMError.unreachable(root) }
        let parsed = try? JSONSerialization.jsonObject(with: data)
        return ((parsed as? [String: Any]) ?? (parsed as? [[String: Any]])?.first ?? [:], (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func errorMessage(_ json: [String: Any], _ status: Int) -> String {
        ((json["error"] as? [String: Any])?["message"] as? String).map { "Gemini: \($0)" } ?? "Gemini error (\(status))"
    }
}

enum CloudLanguages {
    /// Languages Whisper dictation can be set to (plus auto-detect).
    static let dictation = all + [("auto", "Auto-detect")]
    static let all = [("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian")]
    static func name(_ code: String) -> String { all.first { $0.0 == code }?.1 ?? code }
}
