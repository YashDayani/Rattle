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

struct Settings: Codable, Equatable {
    var shortcut: Shortcut = .fn
    var micUID: String? = nil
    var language: String = "en"
    var model: String = "base.en"
    var soundsEnabled: Bool = true
    var cleanup: CleanupLevel = .light
    var tones: [String: Tone] = [
        StyleCategory.personal.rawValue: .veryCasual,
        StyleCategory.work.rawValue: .casual,
        StyleCategory.email.rawValue: .formal,
        StyleCategory.other.rawValue: .formal
    ]
    var showInDock: Bool = true
    var showFlowBar: Bool = true
    var launchAtLogin: Bool = false
    var userName: String = NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    // AI (any OpenAI-compatible endpoint; defaults to a local LM Studio server)
    var llmBaseURL: String = "http://localhost:1234/v1"
    var llmModel: String = ""
    var llmKey: String = ""
    // Transforms
    var autoTransformID: String? = nil
    var commandModeEnabled: Bool = true
    var commandShortcut: Shortcut = .rightCommand
    // Notetaker
    var notetakerSummaries: Bool = true
    var notetakerCaptureSystemAudio: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Settings()
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? d.shortcut
        micUID = try c.decodeIfPresent(String.self, forKey: .micUID)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        soundsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? d.soundsEnabled
        cleanup = try c.decodeIfPresent(CleanupLevel.self, forKey: .cleanup) ?? d.cleanup
        tones = try c.decodeIfPresent([String: Tone].self, forKey: .tones) ?? d.tones
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        showFlowBar = try c.decodeIfPresent(Bool.self, forKey: .showFlowBar) ?? d.showFlowBar
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? d.userName
        llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? d.llmBaseURL
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? d.llmModel
        llmKey = try c.decodeIfPresent(String.self, forKey: .llmKey) ?? d.llmKey
        autoTransformID = try c.decodeIfPresent(String.self, forKey: .autoTransformID)
        commandModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .commandModeEnabled) ?? d.commandModeEnabled
        commandShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .commandShortcut) ?? d.commandShortcut
        notetakerSummaries = try c.decodeIfPresent(Bool.self, forKey: .notetakerSummaries) ?? d.notetakerSummaries
        notetakerCaptureSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .notetakerCaptureSystemAudio) ?? d.notetakerCaptureSystemAudio
    }

    enum Keys: String, CodingKey {
        case shortcut, micUID, language, model, soundsEnabled, cleanup, tones, showInDock, showFlowBar, launchAtLogin, userName
        case llmBaseURL, llmModel, llmKey, autoTransformID, commandModeEnabled, commandShortcut, notetakerSummaries, notetakerCaptureSystemAudio
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
    @Published var scratchpad: String = "" { didSet { try? scratchpad.write(to: url("scratchpad.txt"), atomically: true, encoding: .utf8) } }

    static let supportDir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rattle")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private var loading = true

    private init() {
        history = load("history") ?? []
        dictionary = load("dictionary") ?? []
        snippets = load("snippets") ?? []
        settings = load("settings") ?? Settings()
        customTransforms = load("transforms") ?? []
        meetings = load("meetings") ?? []
        scratchpad = (try? String(contentsOf: url("scratchpad.txt"), encoding: .utf8)) ?? ""
        loading = false
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
