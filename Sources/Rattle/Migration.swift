import SwiftUI
import SQLite3
import AppKit

/// What an import added, shown in the Migration tab.
struct MigrationResult {
    var history = 0, dictionary = 0, snippets = 0, notes = 0, meetings = 0
    var summary: String {
        let parts = [("dictation", history), ("dictionary word", dictionary), ("snippet", snippets), ("note", notes), ("meeting", meetings)]
            .filter { $0.1 > 0 }.map { "\($0.1) \($0.0)\($0.1 == 1 ? "" : "s")" }
        return parts.isEmpty ? "Nothing new to import. Everything is already in Rattle." : "Imported " + parts.joined(separator: ", ") + "."
    }
}

enum Migration {
    struct Failure: LocalizedError { let message: String; init(_ m: String) { message = m }; var errorDescription: String? { message } }

    private static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    static var wisprDir: URL { support.appendingPathComponent("Wispr Flow") }
    static var wisprAvailable: Bool { FileManager.default.fileExists(atPath: wisprDir.appendingPathComponent("flow.sqlite").path) }

    // MARK: Wispr Flow

    @MainActor
    static func importWisprFlow(into store: AppStore) throws -> MigrationResult {
        guard wisprAvailable else { throw Failure("Wispr Flow's data wasn't found on this Mac.") }
        // Work on a copy (with its write-ahead log) so a running Wispr Flow is never touched.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rattle-wispr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for f in ["flow.sqlite", "flow.sqlite-wal", "flow.sqlite-shm"] {
            let src = wisprDir.appendingPathComponent(f)
            if FileManager.default.fileExists(atPath: src.path) { try FileManager.default.copyItem(at: src, to: tmp.appendingPathComponent(f)) }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("flow.sqlite").path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw Failure("Couldn't open Wispr Flow's database.")
        }
        defer { sqlite3_close(db) }

        var result = MigrationResult()

        var haveHistory = Set(store.history.map(\.id))
        var newHistory: [HistoryItem] = []
        query(db, "select transcriptEntityId, timestamp, asrText, formattedText, editedText, duration, app from History where coalesce(formattedText, asrText, '') != ''") { r in
            guard let id = uuid(r.text(0)), !haveHistory.contains(id), let date = parseDate(r.text(1)) else { return }
            let text = (nonEmpty(r.text(4)) ?? nonEmpty(r.text(3)) ?? r.text(2) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let bundle = nonEmpty(r.text(6))
            newHistory.append(HistoryItem(id: id, date: date, raw: r.text(2) ?? text, text: text, duration: r.double(5),
                                          appName: bundle?.split(separator: ".").last.map(String.init) ?? "Unknown", bundleID: bundle))
            haveHistory.insert(id)
        }
        result.history = newHistory.count

        var words = Set(store.dictionary.map { $0.word.lowercased() })
        var triggers = Set(store.snippets.map { $0.trigger.lowercased() })
        var newWords: [DictionaryEntry] = [], newSnippets: [Snippet] = []
        query(db, "select id, phrase, replacement, isSnippet from Dictionary where isDeleted = 0") { r in
            guard let phrase = nonEmpty(r.text(1)) else { return }
            let id = uuid(r.text(0)) ?? UUID(), key = phrase.lowercased()
            if r.int(3) != 0 {
                guard let exp = nonEmpty(r.text(2)), !triggers.contains(key) else { return }
                newSnippets.append(Snippet(id: id, trigger: phrase, expansion: exp)); triggers.insert(key)
            } else if !words.contains(key) {
                newWords.append(DictionaryEntry(id: id, word: phrase, replacement: nonEmpty(r.text(2)))); words.insert(key)
            }
        }
        result.dictionary = newWords.count; result.snippets = newSnippets.count

        let haveNotes = Set(store.notes.map(\.id))
        var newNotes: [Note] = []
        query(db, "select id, title, content, createdAt, modifiedAt, pinned from Notes where isDeleted = 0") { r in
            guard let id = uuid(r.text(0)), !haveNotes.contains(id) else { return }
            let text = nonEmpty(r.text(2)) ?? r.text(1) ?? ""
            newNotes.append(Note(id: id, text: text, created: parseDate(r.text(3)) ?? Date(), updated: parseDate(r.text(4)) ?? Date(), pinned: r.int(5) != 0))
        }
        result.notes = newNotes.count

        let haveMeetings = Set(store.meetings.map(\.id))
        var newMeetings: [Meeting] = []
        query(db, "select id, title, createdAt, summary, recordedMs from Meetings where isDeleted = 0 and isTourDemo = 0") { r in
            guard let raw = r.text(0), let id = uuid(raw), !haveMeetings.contains(id) else { return }
            let lines = wisprTranscript(meetingID: raw)
            let dur = r.double(4) / 1000
            newMeetings.append(Meeting(id: id, title: r.text(1) ?? "Meeting", date: parseDate(r.text(2)) ?? Date(),
                                       duration: dur > 0 ? dur : (lines.last?.time ?? 0), lines: lines, summary: r.text(3) ?? ""))
        }
        result.meetings = newMeetings.count

        // Assign once per collection so each triggers a single save.
        if !newHistory.isEmpty { store.history = (store.history + newHistory).sorted { $0.date > $1.date } }
        if !newWords.isEmpty { store.dictionary += newWords }
        if !newSnippets.isEmpty { store.snippets += newSnippets }
        if !newNotes.isEmpty { store.notes += newNotes }
        if !newMeetings.isEmpty { store.meetings = (store.meetings + newMeetings).sorted { $0.date > $1.date } }
        return result
    }

    /// Reads a meeting transcript from Wispr's NDJSON files (the refined version when it exists).
    private static func wisprTranscript(meetingID: String) -> [TranscriptLine] {
        let dir = wisprDir.appendingPathComponent("meetings/\(meetingID)")
        for name in ["refined.ndjson", "live.ndjson"] {
            guard let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
            var lines: [TranscriptLine] = []
            for raw in text.split(separator: "\n") {
                guard let o = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                      let t = (o["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
                let sp = o["speaker"] as? [String: Any]
                let who = (sp?["source"] as? String) == "mic" ? "You" : ((sp?["name"] as? String) ?? "Others")
                let secs = (o["timestamp"] as? String)?.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) } ?? 0
                lines.append(TranscriptLine(time: secs, speaker: who, text: t))
            }
            if !lines.isEmpty { return lines }
        }
        return []
    }

    // MARK: Granola

    /// Granola keeps its local data encrypted, so import comes from its CSV export (a .csv, or the .zip Granola
    /// produces), plus single exported notes (Markdown, text or JSON). Each note becomes a meeting with its
    /// summary as the notes; only title, summary and date are used.
    @MainActor
    static func importGranola(files: [URL], into store: AppStore) throws -> MigrationResult {
        var existing = Set(store.meetings.map { $0.title.lowercased() + "|" + String(Int($0.date.timeIntervalSince1970 / 86400)) })
        var haveIDs = Set(store.meetings.map(\.id))
        var new: [Meeting] = []
        func add(id: UUID? = nil, title: String, date: Date, body: String) {
            let body = unescapeMarkdown(body).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased() + "|" + String(Int(date.timeIntervalSince1970 / 86400))
            if let id, haveIDs.contains(id) { return }
            guard !body.isEmpty, !existing.contains(key) else { return }
            existing.insert(key)
            let m = Meeting(id: id ?? UUID(), title: title, date: date, duration: 0, lines: [], summary: body)
            haveIDs.insert(m.id); new.append(m)
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rattle-granola-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var all: [URL] = []
        for url in files {
            if url.pathExtension.lowercased() == "zip" {
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let dest = tmp.appendingPathComponent(UUID().uuidString)
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                p.arguments = ["-q", "-o", url.path, "-d", dest.path]
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else { throw Failure("Couldn't open \(url.lastPathComponent).") }
                all += (FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                    .filter { $0.pathExtension.lowercased() == "csv" }
            } else { all.append(url) }
        }

        for url in all {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if url.pathExtension.lowercased() == "csv" {
                for r in CSV.records(raw) {
                    guard let title = nonEmpty(r["document_title"]) ?? nonEmpty(r["title"]) else { continue }
                    let body = nonEmpty(r["summary"]) ?? r["notes"] ?? ""
                    add(id: UUID(uuidString: r["document_id"] ?? ""), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        date: parseDate(r["document_created"] ?? r["created_at"]) ?? Date(), body: body)
                }
                continue
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            var date = (attrs?[.creationDate] as? Date) ?? Date()
            var title = url.deletingPathExtension().lastPathComponent
            var body = raw
            if url.pathExtension.lowercased() == "json", let o = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] {
                title = (o["title"] as? String) ?? title
                if let s = (o["created_at"] as? String) ?? (o["createdAt"] as? String), let d = parseDate(s) { date = d }
                body = (o["notes_markdown"] as? String) ?? (o["summary"] as? String) ?? (o["notes"] as? String) ?? (o["content"] as? String) ?? raw
            } else if let h = raw.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
                title = String(h.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            add(title: title, date: date, body: body)
        }
        if !new.isEmpty { store.meetings = (store.meetings + new).sorted { $0.date > $1.date } }
        var r = MigrationResult(); r.meetings = new.count
        return r
    }

    /// Granola's export backslash-escapes Markdown punctuation (\& \~ \_ …); drop those so it reads normally.
    private static func unescapeMarkdown(_ s: String) -> String {
        // Drop Granola's trailing "Chat with meeting transcript: <link>" footer (and the rule above it).
        let body = s.replacingOccurrences(of: #"(?s)\s*(---\s*)?Chat with meeting transcript:.*$"#, with: "", options: .regularExpression)
        return body.replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!&~<>|$%@^=:;,"'/])"#, with: "$1", options: .regularExpression)
    }

    // MARK: SQLite helpers

    struct Row {
        let stmt: OpaquePointer?
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    }

    private static func query(_ db: OpaquePointer?, _ sql: String, _ each: (Row) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { each(Row(stmt: stmt)) }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    /// Wispr ids are UUIDs; anything else maps to a stable UUID so re-imports don't duplicate.
    private static func uuid(_ s: String?) -> UUID? {
        guard let s else { return nil }
        return UUID(uuidString: s)
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard var s else { return nil }
        s = s.replacingOccurrences(of: " +00:00", with: "Z").replacingOccurrences(of: " ", with: "T")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Writes Rattle's data out as one CSV per kind, in a new folder.
@MainActor
enum Export {
    static func csv(from store: AppStore, into parent: URL) throws -> (folder: URL, summary: String) {
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HHmm"
        let folder = parent.appendingPathComponent("Rattle Export \(stamp.string(from: Date()))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        let folderNames = Dictionary(uniqueKeysWithValues: store.folders.map { ($0.id, $0.name) })

        let files: [(String, [[String]])] = [
            ("dictations", [["id", "date", "app", "text", "raw_text", "words", "duration_seconds"]]
                + store.history.map { [$0.id.uuidString, iso.string(from: $0.date), $0.appName, $0.text, $0.raw, "\($0.words)", String(format: "%.1f", $0.duration)] }),
            ("meetings", [["id", "title", "date", "duration_minutes", "notes", "transcript"]]
                + store.meetings.map { [$0.id.uuidString, $0.title, iso.string(from: $0.date), "\(Int(($0.duration / 60).rounded()))", $0.summary, NotetakerController.transcriptText($0.lines)] }),
            ("notes", [["id", "title", "folder", "created", "updated", "pinned", "text"]]
                + store.notes.map { [$0.id.uuidString, $0.title, $0.folderID.flatMap { folderNames[$0] } ?? "", iso.string(from: $0.created), iso.string(from: $0.updated), $0.pinned ? "yes" : "no", $0.text] }),
            ("snippets", [["trigger", "expansion"]] + store.snippets.map { [$0.trigger, $0.expansion] }),
            ("dictionary", [["word", "replacement"]] + store.dictionary.map { [$0.word, $0.replacement ?? ""] }),
        ]
        for (name, rows) in files {
            // The byte-order mark makes Excel read the file as UTF-8.
            try ("\u{FEFF}" + CSV.write(rows)).write(to: folder.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8)
        }
        let counts = [(store.history.count, "dictation"), (store.meetings.count, "meeting"), (store.notes.count, "note"), (store.snippets.count, "snippet"), (store.dictionary.count, "dictionary word")]
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return (folder, "Exported " + counts.joined(separator: ", ") + " to “\(folder.lastPathComponent)”.")
    }
}

struct MigrationTab: View {
    @LocalState private var wisprMessage = ""
    @LocalState private var granolaMessage = ""
    @LocalState private var wisprFailed = false
    @LocalState private var granolaFailed = false
    @LocalState private var exportMessage = ""
    @LocalState private var exportFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IMPORT").font(Theme.sans(11, .semibold)).foregroundStyle(Theme.muted)
            Card {
                AppRow(logo: AppLogo(bundleID: "com.electron.wispr-flow"), title: "Wispr Flow",
                       detail: Migration.wisprAvailable ? "History, dictionary, snippets, notes and meetings." : "Not found on this Mac.") {
                    PillButton(title: "Import", prominent: true) { importWispr() }.disabled(!Migration.wisprAvailable)
                }
                AppRow(logo: AppLogo(bundleID: "com.granola.app"), title: "Granola", detail: "Pick the CSV you exported from Granola.", last: true) {
                    PillButton(title: "Choose file…", prominent: true) { importGranola() }
                        .tip("Granola encrypts its data, so export your notes as CSV in Granola first. Markdown, text and JSON notes work too.")
                }
            }
            status(wisprMessage, failed: wisprFailed)
            status(granolaMessage, failed: granolaFailed)

            Text("EXPORT").font(Theme.sans(11, .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
            Card {
                AppRow(logo: AppLogo(symbol: "square.and.arrow.up"), title: "Export as CSV", detail: "All your Rattle data, one file per type.", last: true) {
                    PillButton(title: "Export…", prominent: true) { exportCSV() }
                }
            }
            status(exportMessage, failed: exportFailed)
        }
    }

    @ViewBuilder private func status(_ message: String, failed: Bool) -> some View {
        if !message.isEmpty { Text(message).font(Theme.sans(13)).foregroundStyle(failed ? .red : Theme.muted) }
    }

    private func exportCSV() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Export Here"; p.message = "Choose where to save the Rattle export folder"
        p.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard p.runModal() == .OK, let dir = p.url else { return }
        do {
            let r = try Export.csv(from: AppStore.shared, into: dir)
            exportMessage = r.summary; exportFailed = false
            NSWorkspace.shared.activateFileViewerSelecting([r.folder])
        } catch { exportMessage = "Couldn't export: \(error.localizedDescription)"; exportFailed = true }
    }

    private func importWispr() {
        do { wisprMessage = try Migration.importWisprFlow(into: AppStore.shared).summary; wisprFailed = false }
        catch { wisprMessage = error.localizedDescription; wisprFailed = true }
    }

    private func importGranola() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = true; p.canChooseFiles = true
        p.allowedContentTypes = [.zip, .commaSeparatedText, .plainText, .json, .init(filenameExtension: "md") ?? .plainText]
        p.message = "Choose Granola notes or a folder of exported notes"
        guard p.runModal() == .OK else { return }
        var files: [URL] = []
        for u in p.urls {
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                files += ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [])
                    .filter { ["csv", "zip", "md", "txt", "json"].contains($0.pathExtension.lowercased()) }
            } else { files.append(u) }
        }
        do { granolaMessage = try Migration.importGranola(files: files, into: AppStore.shared).summary; granolaFailed = false }
        catch { granolaMessage = error.localizedDescription; granolaFailed = true }
    }
}

/// A settings row led by an app's logo.
private struct AppRow<Trailing: View>: View {
    let logo: AppLogo
    let title: String
    let detail: String
    var last = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                logo
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.sans(14)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 16)
                trailing
            }.padding(.horizontal, 20).padding(.vertical, 14)
            if !last { Divider().overlay(Theme.line).padding(.horizontal, 20) }
        }
    }
}

/// The installed app's own icon, or a plain icon tile when the app isn't on this Mac.
private struct AppLogo: View {
    var bundleID: String? = nil
    var symbol = "square.and.arrow.down"
    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high).frame(width: 36, height: 36)
        } else {
            Icon(symbol, 18).foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.line))
        }
    }
}
