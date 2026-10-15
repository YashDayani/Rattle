import Foundation

/// A local MCP server over stdio (read-only unless the user allows edits). MCP clients (Claude Desktop, Cursor, Claude Code…) launch
/// `Rattle --mcp` as a child process and talk JSON-RPC over stdin/stdout. It reads Rattle's own JSON files
/// straight from Application Support, so the app doesn't need to be running, and nothing leaves this Mac.
enum MCPServer {
    static let name = "rattle"
    static let version = "1.0"

    /// Runs until the client closes stdin.
    static func run() -> Never {
        // Anything printed to stdout that isn't a JSON-RPC message corrupts the stream, so never print there.
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let batch = obj as? [[String: Any]] {
                let replies = batch.compactMap(handle)
                if !replies.isEmpty { write(replies) }
            } else if let msg = obj as? [String: Any], let reply = handle(msg) {
                send(reply)
            }
        }
        exit(0)
    }

    // MARK: JSON-RPC

    private static func handle(_ msg: [String: Any]) -> [String: Any]? {
        guard let method = msg["method"] as? String else { return nil }   // a response to us; we never send requests
        guard let id = msg["id"] else { return nil }                      // notification: no reply
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            return result(id, [
                "protocolVersion": asked ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": name, "version": version],
                "instructions": "Access to the user's Rattle data: notes, meeting transcripts and summaries, dictation history and snippets. Start with search_rattle, or list_notes / list_meetings. Tools that create, edit or delete notes and meetings are only listed when the user has turned on Allow edits in Rattle."
            ])
        case "ping":
            return result(id, [String: Any]())
        case "tools/list":
            return result(id, ["tools": enabledTools().map { $0.schema }])
        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let tool = enabledTools().first(where: { $0.name == toolName }) else {
                return result(id, content("Unknown or disabled tool: \(toolName). Enable it in Rattle → Settings → MCP.", error: true))
            }
            return result(id, content(tool.run(args)))
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    private static func result(_ id: Any, _ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": r] }
    private static func content(_ text: String, error: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": error]
    }
    private static func send(_ obj: Any) { write(obj) }
    private static func write(_ obj: Any) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(d + Data("\n".utf8))
    }

    // MARK: Data (read fresh on every call so it always matches what the app has saved)

    private static func load<T: Decodable>(_ file: String) -> [T] {
        guard let data = try? Data(contentsOf: AppStore.supportDir.appendingPathComponent(file + ".json")) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([T].self, from: data)) ?? []
    }

    private static func save<T: Encodable>(_ items: [T], _ file: String) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        try? e.encode(items).write(to: AppStore.supportDir.appendingPathComponent(file + ".json"), options: .atomic)
    }

    private static var settings: Settings {
        guard let data = try? Data(contentsOf: AppStore.supportDir.appendingPathComponent("settings.json")) else { return Settings() }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.timeZone = .current; return f }()
    private static func stamp(_ d: Date) -> String { iso.string(from: d) }

    // MARK: Tools

    struct Tool {
        let name: String
        let description: String
        let properties: [String: [String: Any]]
        let required: [String]
        var writes = false
        var destructive = false
        let run: ([String: Any]) -> String
        var schema: [String: Any] {
            ["name": name, "description": description,
             "inputSchema": ["type": "object", "properties": properties, "required": required],
             "annotations": ["readOnlyHint": !writes, "destructiveHint": destructive, "openWorldHint": false]]
        }
    }

    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }

    private static func enabledTools() -> [Tool] {
        let s = settings
        guard s.mcpEnabled else { return [] }
        var t: [Tool] = [searchTool(s)]
        if s.mcpNotes { t += [listNotes, getNote] + (s.mcpAllowEdits ? [createNote, updateNote, deleteNote] : []) }
        if s.mcpMeetings { t += [listMeetings, getMeeting] + (s.mcpAllowEdits ? [updateMeeting, deleteMeeting] : []) }
        if s.mcpDictations { t += [listDictations] }
        if s.mcpSnippets { t += [listSnippets] }
        return t
    }

    private static func clock(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func clip(_ s: String, _ n: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
        return flat.count > n ? String(flat.prefix(n)) + "…" : flat
    }
    private static func limit(_ a: [String: Any], _ def: Int = 20) -> Int { max(1, min(100, (a["limit"] as? Int) ?? def)) }

    private static func snippet(_ text: String, around q: String) -> String {
        guard let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return clip(text, 160) }
        let start = text.index(r.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(r.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + clip(String(text[start..<end]), 200) + (end < text.endIndex ? "…" : "")
    }

    private static func searchTool(_ s: Settings) -> Tool {
        var scope = [String]()
        if s.mcpNotes { scope.append("notes") }
        if s.mcpMeetings { scope.append("meeting transcripts and summaries") }
        if s.mcpDictations { scope.append("dictation history") }
        return Tool(name: "search_rattle",
             description: "Full-text search across the user's Rattle data (\(scope.joined(separator: ", "))). Returns matching items with ids you can pass to get_note / get_meeting.",
             properties: ["query": str("Text to look for (case-insensitive)."), "limit": int("Max results, default 20.")],
             required: ["query"]) { a in
            let q = (a["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return "Provide a non-empty query." }
            let cap = limit(a)
            var hits: [(Date, String)] = []
            func has(_ text: String) -> Bool { text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            if s.mcpNotes {
                for n in (load("notes") as [Note]) where has(n.text) {
                    hits.append((n.updated, "[note] \(n.title) · id \(n.id) · \(stamp(n.updated))\n   \(snippet(n.text, around: q))"))
                }
            }
            if s.mcpMeetings {
                for m in (load("meetings") as [Meeting]) {
                    let transcript = m.lines.map(\.text).joined(separator: " ")
                    if has(m.title) || has(m.summary) || has(transcript) {
                        let where_ = has(m.summary) ? m.summary : (has(transcript) ? transcript : m.title)
                        hits.append((m.date, "[meeting] \(m.title) · id \(m.id) · \(stamp(m.date))\n   \(snippet(where_, around: q))"))
                    }
                }
            }
            if s.mcpDictations {
                for h in (load("history") as [HistoryItem]) where has(h.text) {
                    hits.append((h.date, "[dictation] \(stamp(h.date)) · \(h.appName)\n   \(snippet(h.text, around: q))"))
                }
            }
            hits.sort { $0.0 > $1.0 }
            if hits.isEmpty { return "No matches for “\(q)”." }
            let shown = hits.prefix(cap).map(\.1)
            return "\(hits.count) match\(hits.count == 1 ? "" : "es")" + (hits.count > cap ? " (showing \(cap))" : "") + ":\n\n" + shown.joined(separator: "\n\n")
        }
    }

    private static let listNotes = Tool(name: "list_notes", description: "List the user's Rattle notes, most recently edited first (title, id, date, preview).",
        properties: ["limit": int("Max notes, default 20.")], required: []) { a in
        let notes = (load("notes") as [Note]).sorted { $0.updated > $1.updated }
        if notes.isEmpty { return "No notes." }
        return notes.prefix(limit(a)).map { "• \($0.title)\($0.pinned ? " 📌" : "") · id \($0.id) · \(stamp($0.updated)) · \($0.words) words\n   \(clip($0.preview, 140))" }.joined(separator: "\n")
    }

    private static let getNote = Tool(name: "get_note", description: "Get the full text of one note by id.",
        properties: ["id": str("Note id from list_notes or search_rattle.")], required: ["id"]) { a in
        let id = (a["id"] as? String ?? "").lowercased()
        guard let n = (load("notes") as [Note]).first(where: { $0.id.uuidString.lowercased() == id }) else { return "No note with id \(id)." }
        return "# \(n.title)\nCreated \(stamp(n.created)) · Updated \(stamp(n.updated))\n\n\(n.text)"
    }

    private static let listMeetings = Tool(name: "list_meetings", description: "List meetings recorded in Rattle, newest first (title, id, date, duration, summary preview).",
        properties: ["limit": int("Max meetings, default 20.")], required: []) { a in
        let ms = (load("meetings") as [Meeting]).sorted { $0.date > $1.date }
        if ms.isEmpty { return "No meetings." }
        return ms.prefix(limit(a)).map { "• \($0.title) · id \($0.id) · \(stamp($0.date)) · \(Int($0.duration / 60)) min\n   \(clip($0.summary, 160))" }.joined(separator: "\n")
    }

    private static let getMeeting = Tool(name: "get_meeting", description: "Get a meeting's AI summary and full transcript by id.",
        properties: ["id": str("Meeting id from list_meetings or search_rattle."), "include_transcript": ["type": "boolean", "description": "Include the full transcript (default true)."]], required: ["id"]) { a in
        let id = (a["id"] as? String ?? "").lowercased()
        guard let m = (load("meetings") as [Meeting]).first(where: { $0.id.uuidString.lowercased() == id }) else { return "No meeting with id \(id)." }
        var out = "# \(m.title)\n\(stamp(m.date)) · \(Int(m.duration / 60)) min\n"
        out += m.summary.isEmpty ? "\n(No summary yet.)\n" : "\n## Summary\n\(m.summary)\n"
        if (a["include_transcript"] as? Bool) ?? true {
            out += "\n## Transcript\n" + m.lines.map { "[\(clock($0.time))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
        }
        return out
    }

    private static let listDictations = Tool(name: "list_dictations", description: "List recent dictations (what the user spoke, as inserted), newest first.",
        properties: ["limit": int("Max items, default 20.")], required: []) { a in
        let hs = (load("history") as [HistoryItem]).sorted { $0.date > $1.date }
        if hs.isEmpty { return "No dictations." }
        return hs.prefix(limit(a)).map { "• \(stamp($0.date)) · \($0.appName)\n   \($0.text)" }.joined(separator: "\n")
    }

    private static let listSnippets = Tool(name: "list_snippets", description: "List the user's text snippets (trigger → expansion).",
        properties: [:], required: []) { _ in
        let ss = load("snippets") as [Snippet]
        if ss.isEmpty { return "No snippets." }
        return ss.map { "• \($0.trigger) → \(clip($0.expansion, 200))" }.joined(separator: "\n")
    }

    // MARK: Edit tools (only listed when "Allow edits" is on)

    private static func uuidArg(_ a: [String: Any]) -> UUID? { (a["id"] as? String).flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) } }
    private static func bool(_ v: Any?) -> Bool? { v as? Bool }

    private static let createNote = Tool(name: "create_note", description: "Create a new note. The first line becomes its title.",
        properties: ["text": str("The note's text (Markdown)."), "title": str("Optional title. Defaults to the first line."), "pinned": ["type": "boolean", "description": "Pin the note."]], required: ["text"], writes: true) { a in
        let text = (a["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Provide non-empty text." }
        var notes = load("notes") as [Note]
        var n = Note(text: text, pinned: bool(a["pinned"]) ?? false)
        if let t = a["title"] as? String, !t.isEmpty { n.customTitle = t }
        notes.insert(n, at: 0); save(notes, "notes")
        return "Created note “\(n.title)” · id \(n.id)."
    }

    private static let updateNote = Tool(name: "update_note", description: "Replace a note's text and/or change whether it's pinned. Fields you leave out stay as they are.",
        properties: ["id": str("Note id."), "text": str("New full text for the note."), "title": str("New title."), "pinned": ["type": "boolean", "description": "Pin or unpin."]], required: ["id"], writes: true) { a in
        guard let id = uuidArg(a) else { return "Provide a valid note id." }
        var notes = load("notes") as [Note]
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return "No note with id \(id)." }
        if let t = a["text"] as? String { notes[i].text = t }
        if let t = a["title"] as? String { notes[i].customTitle = t.isEmpty ? nil : t }
        if let p = bool(a["pinned"]) { notes[i].pinned = p }
        notes[i].updated = Date(); save(notes, "notes")
        return "Updated note “\(notes[i].title)”."
    }

    private static let deleteNote = Tool(name: "delete_note", description: "Permanently delete a note. This can't be undone, so confirm with the user first.",
        properties: ["id": str("Note id.")], required: ["id"], writes: true, destructive: true) { a in
        guard let id = uuidArg(a) else { return "Provide a valid note id." }
        var notes = load("notes") as [Note]
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return "No note with id \(id)." }
        let title = notes.remove(at: i).title; save(notes, "notes")
        return "Deleted note “\(title)”."
    }

    private static let updateMeeting = Tool(name: "update_meeting", description: "Rename a meeting and/or replace its notes (summary, Markdown). Fields you leave out stay as they are. The transcript can't be edited.",
        properties: ["id": str("Meeting id."), "title": str("New title."), "summary": str("New notes for the meeting, in Markdown.")], required: ["id"], writes: true) { a in
        guard let id = uuidArg(a) else { return "Provide a valid meeting id." }
        var ms = load("meetings") as [Meeting]
        guard let i = ms.firstIndex(where: { $0.id == id }) else { return "No meeting with id \(id)." }
        if let t = (a["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { ms[i].title = t }
        if let s = a["summary"] as? String { ms[i].summary = s; ms[i].summaryError = nil }
        save(ms, "meetings")
        return "Updated meeting “\(ms[i].title)”."
    }

    private static let deleteMeeting = Tool(name: "delete_meeting", description: "Permanently delete a meeting, including its transcript and saved recording. This can't be undone, so confirm with the user first.",
        properties: ["id": str("Meeting id.")], required: ["id"], writes: true, destructive: true) { a in
        guard let id = uuidArg(a) else { return "Provide a valid meeting id." }
        var ms = load("meetings") as [Meeting]
        guard let i = ms.firstIndex(where: { $0.id == id }) else { return "No meeting with id \(id)." }
        let m = ms.remove(at: i)
        if let url = m.audioURL { try? FileManager.default.removeItem(at: url) }
        save(ms, "meetings")
        return "Deleted meeting “\(m.title)”."
    }
}
