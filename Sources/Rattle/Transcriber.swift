import Foundation

struct WhisperModel: Identifiable, Hashable {
    let id: String       // e.g. base.en
    let title: String
    let size: String
    let multilingual: Bool
    var fileName: String { "ggml-\(id).bin" }
    var remote: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")! }
    var localURL: URL { ModelStore.dir.appendingPathComponent(fileName) }
    var installed: Bool { FileManager.default.fileExists(atPath: localURL.path) }

    static let all: [WhisperModel] = [
        .init(id: "base.en", title: "Base (English)", size: "142 MB", multilingual: false),
        .init(id: "small.en", title: "Small (English)", size: "466 MB", multilingual: false),
        .init(id: "base", title: "Base (Multilingual)", size: "142 MB", multilingual: true),
        .init(id: "small", title: "Small (Multilingual)", size: "466 MB", multilingual: true),
    ]
}

enum ModelStore {
    static let dir: URL = {
        let d = AppStore.supportDir.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
}

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()
    @Published var progress: [String: Double] = [:]
    @Published var error: String?
    private var session: URLSession!
    private var active: [Int: WhisperModel] = [:]

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func download(_ m: WhisperModel) {
        guard progress[m.id] == nil, !m.installed else { return }
        error = nil
        progress[m.id] = 0
        let t = session.downloadTask(with: m.remote)
        active[t.taskIdentifier] = m
        t.resume()
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        guard e > 0 else { return }
        let id = t.taskIdentifier
        MainActor.assumeIsolated { if let m = active[id] { progress[m.id] = Double(w) / Double(e) } }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let id = t.taskIdentifier
        MainActor.assumeIsolated {
            guard let m = active[id] else { return }
            try? FileManager.default.removeItem(at: m.localURL)
            do { try FileManager.default.moveItem(at: loc, to: m.localURL) } catch { self.error = error.localizedDescription }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError err: Error?) {
        let id = t.taskIdentifier
        MainActor.assumeIsolated {
            if let m = active[id] {
                progress[m.id] = nil
                active[id] = nil
                if let err { error = err.localizedDescription }
                objectWillChange.send()
            }
        }
    }
}


/// Keeps one whisper.cpp server running so the model stays loaded between dictations.
final class WhisperServer {
    static let shared = WhisperServer()
    private var process: Process?
    private var modelPath: String?
    private let port = 18765
    private var reaped = false

    var serverPath: String? {
        let bundled = Bundle.main.resourcePath.map { $0 + "/whisper-server" }
        return ([bundled].compactMap { $0 } + ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Kills whisper-servers left behind by a previous Rattle that was force-quit.
    func reapStale() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "whisper-server.*--port \(port)"]
        try? p.run(); p.waitUntilExit()
    }

    func ensure(model: WhisperModel) {
        guard model.installed, let exe = serverPath else { return }
        if let p = process, p.isRunning, modelPath == model.localURL.path { return }
        stop()
        if !reaped { reapStale(); reaped = true; Thread.sleep(forTimeInterval: 0.3) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-m", model.localURL.path, "--host", "127.0.0.1", "--port", "\(port)", "-t", "6"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); process = p; modelPath = model.localURL.path } catch { process = nil }
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil; modelPath = nil
    }

    func transcribe(wav: Data, language: String, prompt: String) async throws -> String {
        let boundary = "rattle-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav); body.append("\r\n".data(using: .utf8)!)
        field("response_format", "json"); field("temperature", "0.0"); field("language", language)
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        // The server needs a moment to load the model right after launch.
        var lastError: Error = URLError(.cannotConnectToHost)
        for _ in 0..<40 {
            do {
                let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String else { throw URLError(.badServerResponse) }
                return text
            } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
                lastError = e
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError
    }
}

/// Groq's hosted Whisper, reached through its OpenAI-compatible transcription endpoint.
struct CloudSpeech: Equatable {
    let key: String
    let model: String

    static let models: [(id: String, title: String)] = [
        ("whisper-large-v3-turbo", "Whisper Large v3 Turbo"),
        ("whisper-large-v3", "Whisper Large v3"),
    ]

    func transcribe(wav: Data, language: String, prompt: String) async throws -> String {
        guard !key.isEmpty else { throw Transcriber.Failure.failed("Add your Groq API key in Settings → Model.") }
        let boundary = "rattle-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav); body.append("\r\n".data(using: .utf8)!)
        field("model", model); field("response_format", "json"); field("temperature", "0")
        if language != "auto" { field("language", language) }
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.upload(for: req, from: body) }
        catch { throw Transcriber.Failure.failed("Couldn't reach Groq. Check your internet connection.") }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw Transcriber.Failure.failed("Groq rejected the API key. Check it in Settings → Model.") }
        guard status == 200, let text = json?["text"] as? String else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            throw Transcriber.Failure.failed(detail.map { "Groq: \($0)" } ?? "Groq returned an unexpected response (\(status)).")
        }
        return text
    }
}

enum Transcriber {
    enum Failure: LocalizedError {
        case noEngine, noModel(String), failed(String)
        var errorDescription: String? {
            switch self {
            case .noEngine: return "whisper.cpp isn't installed. Run: brew install whisper-cpp"
            case .noModel(let m): return "Model \(m) isn't downloaded yet. Open Settings → Model."
            case .failed(let s): return s
            }
        }
    }

    static var enginePath: String? {
        let bundled = Bundle.main.resourcePath.map { $0 + "/whisper-cli" }
        return ([bundled].compactMap { $0 } + ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func transcribe(samples: [Float], model: WhisperModel, language: String, vocabulary: [String], cloud: CloudSpeech? = nil) async throws -> String {
        if let cloud {
            return try await cloud.transcribe(wav: AudioRecorder.wav(from: samples), language: language, prompt: vocabulary.joined(separator: ", "))
        }
        guard model.installed else { throw Failure.noModel(model.title) }
        let lang = model.multilingual ? language : "en"
        if WhisperServer.shared.serverPath != nil {
            WhisperServer.shared.ensure(model: model)
            if let text = try? await WhisperServer.shared.transcribe(wav: AudioRecorder.wav(from: samples), language: lang, prompt: vocabulary.joined(separator: ", ")) {
                return text
            }
        }
        guard let engine = enginePath else { throw Failure.noEngine }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("rattle-\(UUID().uuidString).wav")
        try AudioRecorder.wav(from: samples).write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }

        var args = ["-m", model.localURL.path, "-f", wav.path, "-nt", "-np", "-t", "6"]
        args += ["-l", lang]
        if !vocabulary.isEmpty { args += ["--prompt", vocabulary.joined(separator: ", ")] }

        return try await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: engine)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw Failure.failed("Whisper exited with code \(p.terminationStatus)") }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
