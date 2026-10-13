import SwiftUI

// MARK: - Shared bits

extension Theme {
    static let teal1 = Color(red: 0.106, green: 0.369, blue: 0.353)   // darkest
    static let teal2 = Color(red: 0.180, green: 0.612, blue: 0.576)
    static let teal3 = Color(red: 0.557, green: 0.820, blue: 0.784)
    static let teal4 = Color(red: 0.812, green: 0.929, blue: 0.910)
    static let tan = Color(red: 0.788, green: 0.761, blue: 0.706)
    static let purple = Color(red: 0.573, green: 0.396, blue: 0.769)
    static let page = Color(red: 0.988, green: 0.988, blue: 0.984)
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold) }
    static func caps(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .medium).monospaced() }
}

struct TabBar: View {
    let items: [String]
    @Binding var selection: Int
    var border = true
    var body: some View {
        HStack(spacing: 30) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                Button { selection = i } label: {
                    Text(t).font(.system(size: 15, weight: selection == i ? .semibold : .regular))
                        .foregroundStyle(selection == i ? Theme.ink : Theme.muted)
                        .padding(.bottom, 12)
                        .overlay(alignment: .bottom) { if selection == i { Rectangle().fill(Theme.ink).frame(height: 2) } }
                }.buttonStyle(.plain).pointer()
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { if border { Rectangle().fill(Theme.line).frame(height: 1) } }
    }
}

struct TileCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

enum InsightCategory: String, CaseIterable {
    case ai = "AI prompts", other = "Other tasks", documents = "Documents", personal = "Personal messages", email = "Emails", work = "Work messages"
    var icon: String {
        switch self {
        case .ai: return "cpu"
        case .other: return "infinity"
        case .documents: return "doc.text"
        case .personal: return "bubble.left"
        case .email: return "envelope"
        case .work: return "text.bubble"
        }
    }
    static func from(bundleID: String?) -> InsightCategory {
        guard let b = bundleID?.lowercased() else { return .other }
        let ai = ["com.anthropic.claudefordesktop", "com.openai.chat", "com.todesktop.230313mzl4w4u92", "com.microsoft.vscode", "dev.zed.zed", "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.exafunction.windsurf"]
        let docs = ["com.apple.iwork.pages", "com.microsoft.word", "com.apple.notes", "md.obsidian", "notion.id", "com.apple.textedit", "com.rattle.app"]
        if ai.contains(b) { return .ai }
        if docs.contains(b) { return .documents }
        switch StyleCategory.forBundle(b) {
        case .personal: return .personal
        case .work: return .work
        case .email: return .email
        case .other: return .other
        }
    }
}

// MARK: - Page

struct InsightsPage: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var tab = 0
    @LocalState private var shared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                Text("Insights").font(Theme.title())
                Spacer()
                Button { share() } label: {
                    ZStack {
                        Circle().fill(Theme.card).frame(width: 52, height: 52)
                        Icon(shared ? "checkmark" : "square.and.arrow.up", 19).foregroundStyle(Theme.teal1)
                    }
                }.buttonStyle(.plain).pointer().help("Copy a summary of your stats")
            }
            TabBar(items: ["Your usage", "Your voice"], selection: $tab)
            ScrollView {
                Group { if tab == 0 { UsageTab() } else { VoiceTab() } }.padding(.bottom, 24)
            }
        }
    }

    private func share() {
        let s = "I dictate at \(store.averageWPM) WPM with Rattle: \(store.totalWords) words so far, \(store.streak) day streak."
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        shared = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shared = false }
    }
}

// MARK: - Usage

struct UsageTab: View {
    @ObservedObject var store = AppStore.shared

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                wpmCard
                fixesCard
                totalCard
            }
            HStack(alignment: .top, spacing: 22) {
                usageCard
                streakCard
            }
        }.padding(.top, 18)
    }

    private func label(_ t: String) -> some View { Text(t).font(Theme.caps(11.5)).tracking(1).foregroundStyle(Theme.muted) }

    private var wpmCard: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.averageWPM)").font(.system(size: 36, weight: .medium))
                label("WORDS PER MINUTE")
                ZStack {
                    GaugeArc(progress: min(1, Double(store.averageWPM) / 220)).frame(width: 200, height: 150)
                    VStack(spacing: 2) {
                        Text(store.averageWPM == 0 ? "Say something" : "Typing is ~40").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                        Text(store.averageWPM == 0 ? "—" : String(format: "%.1f× faster", Double(store.averageWPM) / 40)).font(.system(size: 15, weight: .medium))
                    }.offset(y: 6)
                }.frame(maxWidth: .infinity).padding(.top, 8)
            }.padding(26)
        }
    }

    private var fixesCard: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(fmt(store.totalCorrected + store.totalDictFixes)).font(.system(size: 36, weight: .medium))
                label("FIXES MADE BY RATTLE")
                Divider().overlay(Theme.line).padding(.vertical, 14)
                row("\(fmt(store.totalCorrected)) words corrected")
                row("\(fmt(store.totalDictFixes)) dictionary fixes")
                Spacer(minLength: 0)
            }.padding(26).frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ t: String) -> some View { Text(t).font(.system(size: 14.5)).padding(.vertical, 3) }

    private var totalCard: some View {
        let (thisMonth, lastMonth) = monthWords()
        return TileCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(fmt(store.totalWords)).font(.system(size: 36, weight: .medium))
                    Spacer()
                    if lastMonth > 0 {
                        let pct = Int((Double(thisMonth - lastMonth) / Double(lastMonth) * 100).rounded())
                        Label { Text("\(abs(pct))% this month") } icon: { Icon(pct >= 0 ? "arrow.up.right" : "arrow.down.right", 14) }
                            .font(.system(size: 11.5)).padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.white))
                    }
                }
                label("TOTAL WORDS DICTATED")
                Divider().overlay(Theme.line).padding(.vertical, 14)
                HStack(spacing: 8) { Icon("desktopcomputer", 18); Text("Desktop").font(.system(size: 14.5)) }
                Text("\(fmt(store.totalWords)) words").font(.system(size: 14.5))
                Spacer(minLength: 0)
            }.padding(26).frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var usageCard: some View {
        let groups = Dictionary(grouping: store.history) { InsightCategory.from(bundleID: $0.bundleID) }
        let total = max(1, store.history.count)
        let apps = Set(store.history.map { $0.appName }).count
        let rows = InsightCategory.allCases.map { ($0, groups[$0]?.count ?? 0) }.sorted { $0.1 > $1.1 }
        return TileCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Desktop usage").font(.system(size: 24, weight: .medium)).lineLimit(1).fixedSize()
                    Spacer()
                    Text("TOTAL APPS USED | \(apps)").font(Theme.caps(10.5)).tracking(0.6).lineLimit(1)
                }
                VStack(spacing: 16) {
                    ForEach(rows, id: \.0) { cat, n in
                        let pct = Double(n) / Double(total)
                        HStack(spacing: 14) {
                            Icon(cat.icon, 19).frame(width: 24)
                            GeometryReader { geo in
                                let w = max(46, geo.size.width * 0.62 * CGFloat(pct))
                                Text("\(Int((pct * 100).rounded()))%").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: w, height: 32).background(RoundedRectangle(cornerRadius: 4).fill(pct > 0.5 ? Theme.teal1 : (pct > 0.05 ? Theme.teal2 : Theme.teal3)))
                            }.frame(height: 32)
                            Text("\(n) \(cat.rawValue.uppercased())").font(Theme.caps(12)).tracking(0.8).frame(maxWidth: 170, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }.padding(28)
        }
    }

    private var streakCard: some View {
        TileCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(store.streak) day streak").font(.system(size: 24, weight: .medium)).lineLimit(1).fixedSize()
                    Spacer()
                    Text("LONGEST STREAK | \(store.longestStreak) DAY\(store.longestStreak == 1 ? "" : "S")").font(Theme.caps(10.5)).tracking(0.6).lineLimit(1)
                }
                Heatmap(history: store.history)
                HStack(spacing: 6) {
                    Text("More").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    ForEach([Theme.teal1, Theme.teal2, Theme.teal3, Theme.teal4], id: \.self) { RoundedRectangle(cornerRadius: 3).fill($0).frame(width: 16, height: 16) }
                    Text("Less").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }.padding(28)
        }
    }

    private func monthWords() -> (Int, Int) {
        let cal = Calendar.current
        let now = Date()
        let thisM = store.history.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.reduce(0) { $0 + $1.words }
        let last = cal.date(byAdding: .month, value: -1, to: now)!
        let lastM = store.history.filter { cal.isDate($0.date, equalTo: last, toGranularity: .month) }.reduce(0) { $0 + $1.words }
        return (thisM, lastM)
    }

    private func fmt(_ n: Int) -> String { n.formatted(.number) }
}

struct GaugeArc: View {
    var progress: Double
    var body: some View {
        ZStack {
            ArcShape(trim: 1).stroke(Theme.tan.opacity(0.35), style: StrokeStyle(lineWidth: 15, lineCap: .round))
            ArcShape(trim: max(0.02, progress)).stroke(Theme.teal1, style: StrokeStyle(lineWidth: 15, lineCap: .round))
        }.padding(8)
    }
}

struct ArcShape: Shape {
    var trim: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let start = Angle(degrees: 150), end = Angle(degrees: 150 + 240 * trim)
        p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: min(r.width, r.height) / 2, startAngle: start, endAngle: end, clockwise: false)
        return p
    }
}

struct Heatmap: View {
    let history: [HistoryItem]
    private let weeks = 20
    private let cell: CGFloat = 14, gap: CGFloat = 4

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1                       // Sun = 0
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        let words = Dictionary(grouping: history) { cal.startOfDay(for: $0.date) }.mapValues { $0.reduce(0) { $0 + $1.words } }
        let peak = max(1, words.values.max() ?? 1)
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: gap) {
                Color.clear.frame(height: 16)
                ForEach(0..<7, id: \.self) { Text(days[$0]).font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize().frame(height: cell) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { w in
                        let d = cal.date(byAdding: .day, value: w * 7, to: start)!
                        let first = cal.component(.day, from: d) <= 7
                        Text(first ? d.formatted(.dateTime.month(.abbreviated)) : "").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            .fixedSize().frame(width: cell, alignment: .leading)
                    }
                }.frame(height: 14)
                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { w in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { r in
                                let d = cal.date(byAdding: .day, value: w * 7 + r, to: start)!
                                RoundedRectangle(cornerRadius: 3).fill(color(d, today, words, peak)).frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(_ d: Date, _ today: Date, _ words: [Date: Int], _ peak: Int) -> Color {
        if d > today { return Color.black.opacity(0.04) }
        guard let n = words[d], n > 0 else { return Theme.tan.opacity(0.75) }
        let f = Double(n) / Double(peak)
        return f > 0.66 ? Theme.teal1 : f > 0.33 ? Theme.teal2 : f > 0.12 ? Theme.teal3 : Theme.teal4
    }
}

// MARK: - Voice

struct VoiceTab: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var aiBlurb: String? = nil
    @LocalState private var busy = false

    private let stop: Set<String> = ["the", "and", "that", "this", "with", "for", "you", "are", "was", "but", "not", "have", "has", "had", "can", "will", "just", "its", "it's", "i'm", "from", "they", "them", "then", "there", "what", "when", "which", "would", "about", "your", "our", "out", "all", "get", "got", "like", "yeah", "okay", "know", "don't", "i'll", "i've", "gonna", "into", "also", "some", "how", "why", "who", "his", "her", "she", "him", "were", "been", "more", "than", "very", "too"]

    var body: some View {
        let goal = 2000
        let total = store.totalWords
        let remaining = goal - (total % goal)
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.tan.opacity(0.4))
                        Capsule().fill(Theme.purple).frame(width: max(12, g.size.width * CGFloat(total % goal) / CGFloat(goal)))
                    }
                }.frame(height: 10)
                HStack {
                    Text(store.history.last.map { "Created \($0.date.formatted(.dateTime.day().month(.abbreviated).year()))" } ?? "Not created yet").font(.system(size: 13))
                    Spacer()
                    Text("Next update in \(remaining.formatted()) more words").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }.padding(.top, 14)

            TileCard {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(archetype.0).font(Theme.serif(30))
                        Text("VOICE PROFILE").font(Theme.caps(11.5)).tracking(1).foregroundStyle(Theme.muted)
                        Text(aiBlurb ?? archetype.1).font(.system(size: 16)).lineSpacing(5).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                        if store.history.count >= 3 {
                            Button { refine() } label: {
                                Label { Text(busy ? "Writing…" : "Refine with AI") } icon: { Icon("sparkles", 14) }.font(.system(size: 12.5, weight: .medium))
                            }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted).padding(.top, 4).disabled(busy)
                        }
                    }
                    Spacer(minLength: 20)
                    ZStack {
                        Circle().fill(Theme.purple.opacity(0.22)).frame(width: 120, height: 120)
                        Icon("person.wave.2.fill", 58).foregroundStyle(Theme.purple)
                    }
                }.padding(26)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    quote(stats.catchphrase, "CATCHPHRASE")
                    quote(stats.mostUsed, "MOST USED WORD")
                    quote(stats.mostCorrected, "MOST CORRECTED WORD")
                }
                TileCard {
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.91, green: 0.47, blue: 0.33)).frame(width: 52, height: 52)
                            .overlay(Icon("sun.max.fill", 30).foregroundStyle(.white))
                        Text(stats.peak).font(Theme.serif(28)).padding(.top, 8)
                        Text("YOUR PEAK TIME & PLACE").font(Theme.caps(11.5)).tracking(1)
                        Text(stats.peakText).font(.system(size: 16)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                        Spacer(minLength: 0)
                    }.padding(26).frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func quote(_ text: String, _ caption: String) -> some View {
        TileCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(text == "—" ? "—" : "“\(text)”").font(.custom("Georgia-Italic", size: 28)).lineLimit(2).minimumScaleFactor(0.6)
                Text(caption).font(Theme.caps(11.5)).tracking(1)
            }.padding(26)
        }
    }

    // MARK: Derived stats (all on-device)
    struct Stats { var catchphrase = "—", mostUsed = "—", mostCorrected = "—", peak = "—", peakText = "Dictate a bit more and your peak time shows up here.", topApp = "" }

    private var stats: Stats {
        var s = Stats()
        guard !store.history.isEmpty else { return s }
        var words: [String: Int] = [:], tri: [String: Int] = [:], fixed: [String: Int] = [:], apps: [String: Int] = [:]
        let fillers: Set<String> = ["um", "uh", "uhm", "erm", "er", "ah", "hmm", "mm"]
        let cal = Calendar.current
        var slots: [String: Int] = [:]
        for h in store.history {
            let toks = h.text.lowercased().split { !($0.isLetter || $0 == "'") }.map(String.init)
            for t in toks where t.count >= 3 && !stop.contains(t) { words[t, default: 0] += 1 }
            if toks.count >= 3 { for i in 0...(toks.count - 3) {
                let g = Array(toks[i..<i + 3]); if g.contains(where: { !stop.contains($0) }) { tri[g.joined(separator: " "), default: 0] += 1 } } }
            for t in h.raw.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) where fillers.contains(t) { fixed[t, default: 0] += 1 }
            apps[h.appName, default: 0] += h.words
            let key = "\(cal.component(.weekday, from: h.date))-\(cal.component(.hour, from: h.date))"
            slots[key, default: 0] += h.words
        }
        for d in store.dictionary where d.replacement != nil {
            let n = store.history.filter { $0.text.localizedCaseInsensitiveContains(d.replacement!) }.count
            if n > 0 { fixed[d.word.lowercased(), default: 0] += n }
        }
        if let t = tri.filter({ $0.value >= 2 }).max(by: { $0.value < $1.value }) { s.catchphrase = t.key.prefix(1).uppercased() + t.key.dropFirst() }
        else if let first = store.history.first?.text.split(separator: " ").prefix(4).joined(separator: " ") { s.catchphrase = first }
        s.mostUsed = words.max(by: { $0.value < $1.value })?.key ?? "—"
        s.mostCorrected = fixed.max(by: { $0.value < $1.value })?.key ?? "—"
        s.topApp = apps.max(by: { $0.value < $1.value })?.key ?? ""
        if let best = slots.max(by: { $0.value < $1.value }) {
            let p = best.key.split(separator: "-").compactMap { Int($0) }
            let day = cal.weekdaySymbols[p[0] - 1]
            let hr = p[1] % 12 == 0 ? 12 : p[1] % 12
            let ap = p[1] < 12 ? "am" : "pm"
            s.peak = "\(day) at \(hr)\(ap)"
            s.peakText = "You dictate the most on \(day)s around \(hr) \(ap == "am" ? "a.m." : "p.m."), mostly in \(s.topApp.isEmpty ? "your apps" : s.topApp)."
        }
        return s
    }

    private var archetype: (String, String) {
        let h = store.history
        guard !h.isEmpty else { return ("Your voice is waiting", "Dictate a few times and Rattle will describe how you speak: your pace, your habits and where you write.") }
        let avg = Double(store.totalWords) / Double(h.count)
        let name = avg < 8 ? "Quick Commander" : avg < 25 ? "Steady Communicator" : "Long-form Narrator"
        let style = avg < 8 ? "Your dictations are short and direct, built for quick replies and commands." : avg < 25 ? "You speak in clear, medium-length thoughts that read well with little editing." : "You talk through ideas at length, letting Rattle turn flowing speech into finished paragraphs."
        return (name, "\(style) You average \(Int(avg.rounded())) words per dictation at about \(store.averageWPM) words per minute\(stats.topApp.isEmpty ? "." : ", most often in \(stats.topApp).")")
    }

    private func refine() {
        busy = true
        let sample = store.history.prefix(25).map { "- " + $0.text }.joined(separator: "\n")
        Task {
            do {
                aiBlurb = try await LLM.chat(system: "You describe a person's dictation voice in 2 warm, specific sentences (max 50 words), second person, based only on the samples. No preface.", user: sample, settings: store.settings, maxTokens: 200, timeout: 45)
            } catch { aiBlurb = nil }
            busy = false
        }
    }
}
