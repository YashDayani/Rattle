import SwiftUI
import Charts

enum HubPage: String, CaseIterable, Identifiable {
    case dictation = "Dictation", notetaker = "Meetings", insights = "Insights", dictionary = "Dictionary", snippets = "Snippets", style = "Style", transforms = "Transforms", notes = "Notes"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dictation: return "mic"
        case .notetaker: return "record.circle"
        case .transforms: return "wand.and.stars"
        case .insights: return "chart.bar"
        case .dictionary: return "text.book.closed"
        case .snippets: return "scissors"
        case .style: return "textformat"
        case .notes: return "note.text"
        }
    }
}

/// Frames of the sidebar rows (keyed by title), in the window's coordinate space, so their tooltips can be drawn over the content panel.
private struct NavRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct HubView: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var router = Router.shared
    @LocalState private var showBell = false
    @LocalState private var navHoverTarget: String? = nil
    @LocalState private var hoveredNav: String? = nil
    private var page: HubPage { get { router.page } nonmutating set { router.page = newValue } }
    private var collapsed: Bool { router.sidebarCollapsed }

    static let windowRadius: CGFloat = 28
    private let gap: CGFloat = 8        // right and bottom of the panel
    private let titleRow: CGFloat = 52  // window chrome row above the panel
    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: Self.windowRadius - gap, bottomTrailingRadius: Self.windowRadius - gap, topTrailingRadius: 32)
    }

    private var toggleButton: some View {
        Button { withAnimation(Theme.Motion.quick) { router.sidebarCollapsed.toggle() } } label: {
            ChromeIcon(name: "sidebar.left", side: 32).foregroundStyle(Theme.ink)
        }.buttonStyle(.press).pointer().tip(collapsed ? "Show sidebar" : "Hide sidebar")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                sidebar.padding(.top, titleRow).frame(width: collapsed ? 60 : 216)
                ZStack {
                    panelShape.fill(Theme.page).overlay(panelShape.stroke(Theme.line))
                    Group {
                        switch page {
                        case .dictation: DictationPage()
                        case .notetaker: NotetakerPage()
                        case .transforms: TransformsPage()
                        case .insights: InsightsPage()
                        case .dictionary: DictionaryPage()
                        case .snippets: SnippetsPage()
                        case .style: StylePage()
                        case .notes: NotesPage()
                        }
                    }
                    .id(page)
                    .transition(.opacity)
                    .frame(maxWidth: 1046)
                    .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 24)
                }
                .padding(.top, titleRow).padding(.trailing, gap).padding(.bottom, gap)
                .overlay(alignment: .topTrailing) { panelIcons }
            }

            // Sidebar toggle stays on the title row in both states: after the traffic lights when windowed, flush left in full screen.
            toggleButton.frame(height: titleRow).padding(.leading, router.isFullScreen ? 16 : 92)

            if router.showSettings {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { router.showSettings = false }
                SettingsModal(close: { router.showSettings = false }).transition(.scale(scale: 0.97).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: "hubRoot")
        .overlayPreferenceValue(NavRowFrames.self) { frames in navTooltips(frames) }
        .background(Theme.window)
        // The window itself is transparent; this gives it its rounded corners (square in full screen).
        .clipShape(RoundedRectangle(cornerRadius: router.isFullScreen ? 0 : Self.windowRadius, style: .continuous))
        .animation(Theme.Motion.standard, value: router.showSettings)
        .animation(Theme.Motion.standard, value: router.isFullScreen)
        .animation(Theme.Motion.quick, value: page)
    }

    private var panelIcons: some View {
        HStack(spacing: 4) {
            Button { showBell.toggle() } label: { ChromeIcon(name: "bell") }
                .buttonStyle(.press).pointer().tip("Notifications")
                .popover(isPresented: $showBell, arrowEdge: .bottom) {
                    VStack(spacing: 6) {
                        Icon("bell.slash", 25).foregroundStyle(Theme.muted)
                        Text("You’re all caught up").font(Theme.sans(13, .medium))
                        Text("Rattle will tell you here when something needs attention.").font(Theme.sans(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }.padding(18).frame(width: 240)
                }
            Button { router.openSettings(.general) } label: { ChromeIcon(name: "person.crop.circle") }
                .buttonStyle(.press).pointer().tip("Settings", alignEnd: true)
        }
        .foregroundStyle(Theme.ink).frame(height: titleRow).padding(.trailing, 8)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconView(size: 25)
                if !collapsed { Text("Rattle").font(Theme.sans(20, .semibold)) }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.leading, collapsed ? 0 : 5).padding(.vertical, 4).padding(.bottom, 16)

            ForEach(HubPage.allCases) { p in navRow(icon: p.icon, title: p.rawValue, selected: page == p) { page = p } }
            Spacer()
            if !collapsed { SetupChecklist().padding(.bottom, 12) }
            navRow(icon: "gearshape", title: "Settings", selected: false) { router.openSettings(router.settingsTab) }
            navRow(icon: "questionmark.circle", title: "Help", selected: false) { NSWorkspace.shared.open(URL(string: "https://github.com")!) }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    /// One label per row, shown beside it while the sidebar is collapsed and the pointer is on the row.
    /// Dark pill, 12px text, 4px to the right of the row and centred on it; it scales in from 0.9 and fades over 150ms.
    private func navTooltips(_ frames: [String: CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(frames.keys.sorted(), id: \.self) { title in
                if let f = frames[title] {
                    let on = collapsed && hoveredNav == title
                    TipBubble(text: title, on: on)
                        .offset(x: f.maxX + 4, y: f.midY - 16)   // 16 = half the label's 32pt height
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func navRow(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(icon, 20).frame(width: 20, height: 20)
                if !collapsed { Text(title).font(Theme.sans(15, .medium)); Spacer() }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : 8).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(selected ? Theme.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.press).pointer()
        .background(GeometryReader { g in Color.clear.preference(key: NavRowFrames.self, value: [title: g.frame(in: .named("hubRoot"))]) })
        .onHover { inside in
            // A short delay before the collapsed-sidebar label appears, so it doesn't flash while the pointer passes over.
            let wasShowing = hoveredNav != nil
            if inside {
                if wasShowing { hoveredNav = title; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if hoveredNav == nil && navHoverTarget == title { hoveredNav = title } }
                navHoverTarget = title
            } else {
                if navHoverTarget == title { navHoverTarget = nil }
                if hoveredNav == title { hoveredNav = nil }
            }
        }
    }
}

/// Icon button used in the window chrome row: 20pt glyph in a 36pt hit area that tints on hover.
struct ChromeIcon: View {
    let name: String
    var side: CGFloat = 36
    @LocalState private var hover = false
    var body: some View {
        Icon(name, 20).frame(width: 20, height: 20)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(hover ? Theme.selected : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

struct SetupChecklist: View {
    @LocalState private var mic = Permissions.micGranted
    @LocalState private var ax = Permissions.accessibilityGranted
    @LocalState private var model = SetupChecklist.modelReady
    @LocalState private var engine = SetupChecklist.engineReady
    private let t = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static var modelReady: Bool {
        let s = AppStore.shared.settings
        return s.cloudSpeechReady || (WhisperModel.all.first { $0.id == s.model }?.installed ?? false)
    }
    private static var engineReady: Bool { AppStore.shared.settings.cloudSpeechReady || Transcriber.enginePath != nil }

    var done: Int { [mic, ax, model, engine].filter { $0 }.count }

    var body: some View {
        if done < 4 {
            VStack(alignment: .leading, spacing: 9) {
                Text("Set up Rattle").font(Theme.sans(12, .semibold)).foregroundStyle(Theme.ink)
                ProgressView(value: Double(done), total: 4).tint(Theme.teal1)
                row("Microphone access", mic) { Permissions.requestMic { _ in mic = Permissions.micGranted } }
                row("Accessibility (hotkey + paste)", ax) { Permissions.requestAccessibility(); Permissions.openPrivacy("Privacy_Accessibility") }
                row("whisper.cpp engine", engine) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("brew install whisper-cpp", forType: .string) }
                row("Speech model", model) { if let m = WhisperModel.all.first(where: { $0.id == AppStore.shared.settings.model }) { Task { @MainActor in ModelDownloader.shared.download(m) } } }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.line))
            .onReceive(t) { _ in
                mic = Permissions.micGranted; ax = Permissions.accessibilityGranted
                engine = Self.engineReady
                model = Self.modelReady
                if ax { DictationController.shared.retryHotkey() }
            }
        }
    }

    private func row(_ title: String, _ ok: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(ok ? "checkmark.circle.fill" : "circle", 19).foregroundStyle(ok ? Theme.teal3 : Theme.muted)
                Text(title).font(Theme.sans(12)).strikethrough(ok).foregroundStyle(ok ? Theme.muted : Theme.ink)
                Spacer()
            }
        }.buttonStyle(.press).pointer().disabled(ok)
    }
}

// MARK: Pages

struct DictationPage: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var dictation = DictationController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Welcome back, \(store.settings.userName)", subtitle: nil) {
                HStack(spacing: 18) {
                    stat("flame", "\(store.streak) day\(store.streak == 1 ? "" : "s")")
                    stat("text.word.spacing", "\(store.totalWords) words")
                    stat("speedometer", "\(store.averageWPM) WPM")
                }.padding(.top, 10)
            }
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hold \(store.settings.shortcut.title) and speak").font(Theme.sans(15, .semibold))
                        Text("Press space while holding for hands-free. Esc cancels.").font(Theme.sans(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    PillButton(title: dictation.isRecording ? "Stop" : "Try it", prominent: true) { dictation.toggleFromUI() }
                }.padding(.horizontal, 26).padding(.vertical, 24)
            }
            if let e = dictation.lastError { Text(e).font(Theme.sans(12)).foregroundStyle(.red.opacity(0.8)) }

            if store.history.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    IllustrationView(name: Illustration.dictationEmpty, height: 170).padding(.bottom, 12)
                    Text("No dictations yet").font(Theme.serif(22))
                    Text("Click into any text field, hold \(store.settings.shortcut.title), and talk.").foregroundStyle(Theme.muted).font(Theme.sans(14))
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(grouped, id: \.0) { (day, items) in
                            Text(day).font(Theme.sans(12, .semibold)).tracking(0.9).foregroundStyle(Theme.muted).padding(.top, 16).padding(.bottom, 8)
                            VStack(spacing: 0) {
                                ForEach(items) { HistoryRow(item: $0) }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).stroke(Theme.line))
                        }
                    }
                }
            }
        }
    }

    private var grouped: [(String, [HistoryItem])] {
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "EEEE, MMM d"
        var out: [(String, [HistoryItem])] = []
        for h in store.history {
            let key = cal.isDateInToday(h.date) ? "TODAY" : cal.isDateInYesterday(h.date) ? "YESTERDAY" : df.string(from: h.date).uppercased()
            if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1.append(h) } else { out.append((key, [h])) }
        }
        return out
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) { Icon(icon, 15); Text(text).font(Theme.sans(13, .medium)) }.foregroundStyle(Theme.muted)
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    @LocalState private var hover = false
    @LocalState private var copied = false
    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            Text(item.date, style: .time).font(Theme.sans(13)).foregroundStyle(Theme.muted).frame(width: 66, alignment: .leading)
            Text(item.text).font(Theme.sans(15)).lineSpacing(2).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            HStack(spacing: 6) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false } } label: {
                    Icon(copied ? "checkmark" : "doc.on.doc", 16)
                }
                Button { AppStore.shared.history.removeAll { $0.id == item.id } } label: { Icon("trash", 16) }
            }.buttonStyle(.press).pointer().foregroundStyle(Theme.muted).opacity(hover ? 1 : 0)
        }
        .padding(16)
        .background(hover ? Theme.card : .clear)
        .onHover { hover = $0 }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
    }
}

struct DictionaryPage: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var adding = false
    @LocalState private var word = ""
    @LocalState private var replacement = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(title: "Dictionary", subtitle: "Teach Rattle names, jargon and spellings. Add a replacement to rewrite what's heard.") {
                PillButton(title: "Add new", prominent: true) { adding = true }
            }
            if store.dictionary.isEmpty {
                ScrollView { HeroCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HeroHeadline(before: "Words Rattle should ", italic: "never", after: " get wrong.")
                        Text("Add names, jargon and product terms. Give a word a replacement to rewrite what's heard.").font(Theme.sans(17)).foregroundStyle(.white.opacity(0.9)).padding(.bottom, 6)
                        HStack(spacing: 14) { ExamplePill(text: "“tech up labs”", cue: true); Icon("arrow.right", 16).foregroundStyle(.white.opacity(0.8)); ExamplePill(text: "TechUp Labs") }
                        HStack(spacing: 14) { ExamplePill(text: "“kubernetes”", cue: true); Icon("arrow.right", 16).foregroundStyle(.white.opacity(0.8)); ExamplePill(text: "Kubernetes") }
                        Button { adding = true } label: {
                            Text("Add a word").font(Theme.sans(16, .medium)).foregroundStyle(Theme.heroInk).padding(.horizontal, 20).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.heroField))
                        }.buttonStyle(.press).pointer().padding(.top, 14)
                    }
                } }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.dictionary) { e in
                            HStack {
                                Text(e.word).font(Theme.sans(14, .medium))
                                if let r = e.replacement, !r.isEmpty { Icon("arrow.right", 14).foregroundStyle(Theme.muted); Text(r).font(Theme.sans(14)) }
                                Spacer()
                                Button { store.dictionary.removeAll { $0.id == e.id } } label: { Icon("trash", 16) }.buttonStyle(.press).pointer().foregroundStyle(Theme.muted)
                            }.padding(.horizontal, 22).padding(.vertical, 17).overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
                        }
                    }.background(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.line))
                }
            }
        }
        .sheet(isPresented: $adding) {
            EntrySheet(title: "Add to dictionary", f1: "Word or phrase", f2: "Replace with (optional)", v1: $word, v2: $replacement, multiline: false) {
                store.dictionary.insert(DictionaryEntry(word: word, replacement: replacement.isEmpty ? nil : replacement), at: 0)
                word = ""; replacement = ""; adding = false
            } cancel: { adding = false }
        }
    }
}

struct EntrySheet: View {
    let title: String, f1: String, f2: String
    @Binding var v1: String
    @Binding var v2: String
    let multiline: Bool
    var save: () -> Void
    var cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Theme.serif(24))
            TextField(f1, text: $v1).textFieldStyle(.roundedBorder)
            if multiline { TextEditor(text: $v2).font(Theme.sans(13)).frame(height: 110).overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.line)) }
            else { TextField(f2, text: $v2).textFieldStyle(.roundedBorder) }
            HStack { Spacer(); PillButton(title: "Cancel", action: cancel); PillButton(title: "Save", prominent: true, action: save) }
        }.padding(24).frame(width: 420)
    }
}

struct StylePage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(title: "Style", subtitle: "Choose how Rattle formats your dictations in different apps.") { EmptyView() }
            ScrollView { VStack(spacing: 28) {
            Card {
                ForEach(Array(StyleCategory.allCases.enumerated()), id: \.element) { i, c in
                    SettingRow(title: c.title, detail: c.apps, last: i == StyleCategory.allCases.count - 1) {
                        Dropdown(selection: Binding(get: { store.settings.tones[c.rawValue] ?? .formal }, set: { store.settings.tones[c.rawValue] = $0 }),
                                 options: Tone.allCases.map { ($0, $0.title) }, width: 160)
                    }
                }
            }
            Card {
                SettingRow(title: "Auto cleanup", detail: store.settings.cleanup.detail, last: true) {
                    Dropdown(selection: $store.settings.cleanup, options: CleanupLevel.allCases.map { ($0, $0.title) }, width: 160)
                }
            }
            } }
        }
    }
}
