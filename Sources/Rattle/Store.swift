import Foundation
import Combine

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var raw: String
    var text: String
    var duration: Double
    var appName: String
    var bundleID: String? = nil
    var corrected: Int? = nil     // filler words / stutters removed
    var dictFixes: Int? = nil     // dictionary replacements applied
    var words: Int { text.split { $0.isWhitespace }.count }
}

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    var replacement: String?
}

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var created = Date()
    var updated = Date()
    var pinned = false
    /// Optional explicit title. Empty falls back to the first line of the text.
    var customTitle: String? = nil
    var folderID: UUID? = nil

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: true).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    /// The first non-empty line.
    var title: String {
        if let t = customTitle?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        return lines.first.map { Note.plain($0.trimmingCharacters(in: .whitespaces)) } ?? "New note"
    }
    /// Body shown on cards: everything after the first-line title (or all of it when there is a custom title), Markdown markers stripped.
    var preview: String {
        let hasTitle = !(customTitle?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        return (hasTitle ? lines[...] : lines.dropFirst()).map { Note.plain($0.trimmingCharacters(in: .whitespaces)) }.joined(separator: "\n")
    }
    /// Strips leading Markdown markers (#, >, -, *, 1.) and inline emphasis for display.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"^(#{1,6}\s+|>\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\*\*|__|`|\*)"#, with: "", options: .regularExpression)
        return t
    }
    /// True when pasted text looks like Markdown worth rendering.
    static func looksLikeMarkdown(_ s: String) -> Bool {
        s.range(of: #"(?m)^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>\s|```|\|.*\|)"#, options: .regularExpression) != nil
            || s.contains("**") || s.range(of: #"\[[^\]]+\]\([^)]+\)"#, options: .regularExpression) != nil
    }
    var words: Int { text.split { $0 == " " || $0.isNewline }.count }
    /// Time for today, "Yesterday", otherwise the date.
    var updatedLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(updated) { return updated.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(updated) { return "Yesterday" }
        return updated.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

struct Folder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var created = Date()
}

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

struct Transform: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var prompt: String
    var builtIn: Bool = false
}

struct TranscriptLine: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Double          // seconds from meeting start
    var speaker: String       // "You" / "Others"
    var text: String
}

struct Meeting: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var duration: Double
    var lines: [TranscriptLine]
    var summary: String = ""
    var summaryError: String? = nil
    var capturedSystemAudio: Bool = false
    /// File name of the meeting's recording inside `AppStore.recordingsDir`, if one was saved.
    var audioFile: String? = nil

    var audioURL: URL? {
        guard let f = audioFile else { return nil }
        let u = AppStore.recordingsDir.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

enum Tone: String, Codable, CaseIterable, Identifiable {
    case formal, casual, veryCasual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Very casual"
        }
    }
    var example: String {
        switch self {
        case .formal: return "Caps + punctuation"
        case .casual: return "Caps + less punctuation"
        case .veryCasual: return "No caps + less punctuation"
        }
    }
}

enum StyleCategory: String, Codable, CaseIterable, Identifiable {
    case personal, work, email, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }
    var apps: String {
        switch self {
        case .personal: return "Messages, WhatsApp, Telegram, Discord"
        case .work: return "Slack, Teams, Zoom"
        case .email: return "Mail, Outlook, Superhuman, Spark"
        case .other: return "Applies to all apps not part of any styles."
        }
    }
    static func forBundle(_ id: String?) -> StyleCategory {
        guard let id = id?.lowercased() else { return .other }
        let personal = ["com.apple.mobilesms", "net.whatsapp.whatsapp", "ru.keepcoder.telegram", "com.hnc.discord", "org.whispersystems.signal-desktop"]
        let work = ["com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "us.zoom.xos"]
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.superhuman.electron", "com.readdle.smartemail-mac"]
        if personal.contains(id) { return .personal }
        if work.contains(id) { return .work }
        if email.contains(id) { return .email }
        return .other
    }
}

enum Shortcut: String, Codable, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand, rightControl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .rightControl: return "Right ⌃"
        }
    }
}

enum CleanupLevel: String, Codable, CaseIterable, Identifiable {
    case none, light, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .high: return "High"
        }
    }
    var detail: String {
        switch self {
        case .none: return "Exactly what Whisper heard."
        case .light: return "Removes filler words and fixes capitalization."
        case .high: return "Also resolves self-corrections and tidies punctuation."
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Where speech is turned into text: whisper.cpp on this Mac, or Groq's hosted Whisper.
enum SpeechEngine: String, Codable, CaseIterable, Identifiable {
    case local, cloud
    var id: String { rawValue }
}

struct Settings: Codable, Equatable {
    var shortcut: Shortcut = .fn
    var micUID: String? = nil
    var language: String = "en"
    var model: String = "base.en"
    var speechEngine: SpeechEngine = .local
    var groqKey: String = ""
    var groqModel: String = "whisper-large-v3-turbo"
    /// Cloud credentials for the transcriber, or nil when transcribing locally.
    var cloudSpeech: CloudSpeech? { speechEngine == .cloud ? CloudSpeech(key: groqKey, model: groqModel) : nil }
    var cloudSpeechReady: Bool { speechEngine == .cloud && !groqKey.isEmpty }
    /// Speech model for meeting transcripts: "" follows dictation, otherwise "local:<whisper id>" or "cloud:<groq model>".
    var meetingSpeechModel: String = ""
    /// The speech model and cloud credentials meeting transcription uses.
    var meetingSpeech: (model: WhisperModel, cloud: CloudSpeech?) {
        let dictation = WhisperModel.all.first { $0.id == model } ?? WhisperModel.all[0]
        let parts = meetingSpeechModel.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (dictation, cloudSpeech) }
        if parts[0] == "cloud" { return (dictation, CloudSpeech(key: groqKey, model: parts[1])) }
        return (WhisperModel.all.first { $0.id == parts[1] } ?? dictation, nil)
    }
    var soundsEnabled: Bool = true
    var cleanup: CleanupLevel = .light
    var tones: [String: Tone] = [
        StyleCategory.personal.rawValue: .veryCasual,
        StyleCategory.work.rawValue: .casual,
        StyleCategory.email.rawValue: .formal,
        StyleCategory.other.rawValue: .formal
    ]
    var appearance: AppearanceMode = .system
    var showInDock: Bool = true
    var showFlowBar: Bool = true
    var launchAtLogin: Bool = false
    var userName: String = NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    // AI (any OpenAI-compatible endpoint; defaults to a local LM Studio server)
    var llmBaseURL: String = "http://localhost:1234/v1"
    var llmModel: String = ""
    var llmKey: String = ""
    /// Model for meeting summaries; "" uses llmModel.
    var summaryModel: String = ""
    /// Send the meeting recording (not the transcript) to the summary model when the AI server is Gemini.
    var summaryFromAudio: Bool = true
    // Transforms
    var autoTransformID: String? = nil
    var commandModeEnabled: Bool = true
    var commandShortcut: Shortcut = .rightCommand
    // Notetaker
    var notetakerSummaries: Bool = true
    var notetakerCaptureSystemAudio: Bool = true
    var notetakerSaveAudio: Bool = true
    // MCP (local server other apps launch via `Rattle --mcp`)
    var mcpEnabled: Bool = true
    var mcpNotes: Bool = true
    var mcpMeetings: Bool = true
    var mcpDictations: Bool = true
    var mcpSnippets: Bool = true
    /// Lets connected apps rename, edit and delete notes and meetings. Off until the user turns it on.
    var mcpAllowEdits: Bool = false
    /// False until the first-run onboarding is finished.
    var onboardingDone: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Settings()
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? d.shortcut
        micUID = try c.decodeIfPresent(String.self, forKey: .micUID)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        speechEngine = try c.decodeIfPresent(SpeechEngine.self, forKey: .speechEngine) ?? d.speechEngine
        groqKey = try c.decodeIfPresent(String.self, forKey: .groqKey) ?? d.groqKey
        groqModel = try c.decodeIfPresent(String.self, forKey: .groqModel) ?? d.groqModel
        soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? d.soundsEnabled
        cleanup = try c.decodeIfPresent(CleanupLevel.self, forKey: .cleanup) ?? d.cleanup
        tones = try c.decodeIfPresent([String: Tone].self, forKey: .tones) ?? d.tones
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? d.appearance
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        showFlowBar = try c.decodeIfPresent(Bool.self, forKey: .showFlowBar) ?? d.showFlowBar
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? d.userName
        llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? d.llmBaseURL
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? d.llmModel
        llmKey = try c.decodeIfPresent(String.self, forKey: .llmKey) ?? d.llmKey
        summaryModel = try c.decodeIfPresent(String.self, forKey: .summaryModel) ?? d.summaryModel
        summaryFromAudio = try c.decodeIfPresent(Bool.self, forKey: .summaryFromAudio) ?? d.summaryFromAudio
        meetingSpeechModel = try c.decodeIfPresent(String.self, forKey: .meetingSpeechModel) ?? d.meetingSpeechModel
        autoTransformID = try c.decodeIfPresent(String.self, forKey: .autoTransformID)
        commandModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandModeEnabled) ?? d.commandModeEnabled
        commandShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .commandShortcut) ?? d.commandShortcut
        notetakerSummaries = try c.decodeIfPresent(Bool.self, forKey: .notetakerSummaries) ?? d.notetakerSummaries
        notetakerCaptureSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .notetakerCaptureSystemAudio) ?? d.notetakerCaptureSystemAudio
        notetakerSaveAudio = try c.decodeIfPresent(Bool.self, forKey: .notetakerSaveAudio) ?? d.notetakerSaveAudio
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? d.mcpEnabled
        mcpNotes = try c.decodeIfPresent(Bool.self, forKey: .mcpNotes) ?? d.mcpNotes
        mcpMeetings = try c.decodeIfPresent(Bool.self, forKey: .mcpMeetings) ?? d.mcpMeetings
        mcpDictations = try c.decodeIfPresent(Bool.self, forKey: .mcpDictations) ?? d.mcpDictations
        mcpSnippets = try c.decodeIfPresent(Bool.self, forKey: .mcpSnippets) ?? d.mcpSnippets
        mcpAllowEdits = try c.decodeIfPresent(Bool.self, forKey: .mcpAllowEdits) ?? d.mcpAllowEdits
        // A settings file from before onboarding existed belongs to someone already using Rattle.
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? true
    }

    enum Keys: String, CodingKey {
        case shortcut, micUID, language, model, soundsEnabled, cleanup, tones, appearance, showInDock, showFlowBar, launchAtLogin, userName
        case speechEngine, groqKey, groqModel, meetingSpeechModel, summaryModel, summaryFromAudio
        case llmBaseURL, llmModel, llmKey, autoTransformID, commandModeEnabled, commandShortcut, notetakerSummaries, notetakerCaptureSystemAudio, notetakerSaveAudio
        case mcpEnabled, mcpNotes, mcpMeetings, mcpDictations, mcpSnippets, mcpAllowEdits, onboardingDone
    }
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var history: [HistoryItem] = [] { didSet { save(history, "history") } }
    @Published var dictionary: [DictionaryEntry] = [] { didSet { save(dictionary, "dictionary") } }
    @Published var snippets: [Snippet] = [] { didSet { save(snippets, "snippets") } }
    @Published var settings = Settings() { didSet { save(settings, "settings") } }
    @Published var customTransforms: [Transform] = [] { didSet { save(customTransforms, "transforms") } }
    @Published var meetings: [Meeting] = [] { didSet { save(meetings, "meetings") } }
    @Published var notes: [Note] = [] { didSet { save(notes, "notes") } }
    @Published var folders: [Folder] = [] { didSet { save(folders, "folders") } }

    nonisolated static let supportDir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rattle")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    nonisolated static let recordingsDir: URL = {
        let d = supportDir.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private var loading = true

    /// Whether Rattle has been used from this folder before: any saved data, or a downloaded speech model.
    nonisolated static func hasPriorUse(in dir: URL) -> Bool {
        let fm = FileManager.default
        if ["history", "notes", "meetings", "dictionary", "snippets"].contains(where: { fm.fileExists(atPath: dir.appendingPathComponent("\($0).json").path) }) { return true }
        let models = (try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent("models").path)) ?? []
        return models.contains { $0.hasSuffix(".bin") }
    }

    private init() {
        history = load("history") ?? []
        dictionary = load("dictionary") ?? []
        snippets = load("snippets") ?? []
        if let saved: Settings = load("settings") { settings = saved }
        else {
            // No settings file yet. Someone who kept every default still has history or a model on disk.
            var fresh = Settings(); fresh.onboardingDone = Self.hasPriorUse(in: Self.supportDir); settings = fresh
        }
        customTransforms = load("transforms") ?? []
        meetings = load("meetings") ?? []
        folders = load("folders") ?? []
        if let saved: [Note] = load("notes") {
            notes = saved
        } else if let old = try? String(contentsOf: url("scratchpad.txt"), encoding: .utf8), !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // First launch with Notes: carry the old Scratchpad text over as a note. scratchpad.txt is left in place.
            notes = [Note(text: old)]
        }
        loading = false
        for n in Self.watched { seen[n] = modified(n) }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.reloadExternalChanges() } }
    }

    // Other processes (the MCP server) can edit these files. Pick those edits up, and never save while applying them.
    private static let watched = ["meetings", "notes", "folders", "snippets", "dictionary"]
    private var seen: [String: Date] = [:]
    private func modified(_ name: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(name + ".json").path))?[.modificationDate] as? Date
    }
    private func reloadExternalChanges() {
        for n in Self.watched {
            let m = modified(n)
            guard m != seen[n] else { continue }
            seen[n] = m
            loading = true; defer { loading = false }
            switch n {
            case "meetings": if let v: [Meeting] = load(n) { meetings = v }
            case "notes": if let v: [Note] = load(n) { notes = v }
            case "folders": if let v: [Folder] = load(n) { folders = v }
            case "snippets": if let v: [Snippet] = load(n) { snippets = v }
            default: if let v: [DictionaryEntry] = load(n) { dictionary = v }
            }
        }
    }

    private func url(_ name: String) -> URL { Self.supportDir.appendingPathComponent(name) }

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name + ".json")) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        if loading { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        try? e.encode(value).write(to: url(name + ".json"), options: .atomic)
        if Self.watched.contains(name) { seen[name] = modified(name) }
    }

    var allTransforms: [Transform] { Transforms.builtIns + customTransforms }
    func transform(id: String?) -> Transform? { id.flatMap { i in allTransforms.first { $0.id == i } } }

    // MARK: Stats
    var totalWords: Int { history.reduce(0) { $0 + $1.words } }
    var totalDictations: Int { history.count }
    var averageWPM: Int {
        let secs = history.reduce(0) { $0 + $1.duration }
        guard secs > 5 else { return 0 }
        return Int(Double(totalWords) / (secs / 60))
    }
    var streak: Int {
        let cal = Calendar.current
        let days = Set(history.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days.contains(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(history.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        return best
    }
    var totalCorrected: Int { history.reduce(0) { $0 + ($1.corrected ?? 0) } }
    var totalDictFixes: Int { history.reduce(0) { $0 + ($1.dictFixes ?? 0) } }
    func wordsPerDay(last n: Int) -> [(Date, Int)] {
        let cal = Calendar.current
        return (0..<n).reversed().map { off in
            let day = cal.date(byAdding: .day, value: -off, to: cal.startOfDay(for: Date()))!
            let w = history.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.words }
            return (day, w)
        }
    }
    var minutesSaved: Int {
        // Typing at ~40 wpm vs. speaking time.
        let typing = Double(totalWords) / 40.0
        let speaking = history.reduce(0) { $0 + $1.duration } / 60
        return max(0, Int(typing - speaking))
    }
}
