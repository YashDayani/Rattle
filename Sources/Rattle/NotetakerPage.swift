import SwiftUI

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var page: HubPage = .dictation
    @Published var showSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var sidebarCollapsed = false
    @Published var isFullScreen = false
    /// Note open in the Notes page editor, if any.
    @Published var openNoteID: UUID?
    func openSettings(_ tab: SettingsTab) { settingsTab = tab; showSettings = true }
}

/// Renders the Markdown that notes use: headings (# to ######), nested bullets, numbered lists, checkboxes,
/// quotes, code blocks, tables, rules, and inline bold/italic/code/links.
struct MarkdownLite: View {
    let text: String

    private enum Block {
        case heading(Int, String), bullet(Int, String), numbered(Int, String, String), check(Int, Bool, String)
        case quote(String), code(String), table([[String]]), rule, paragraph(String), gap
    }

    /// Wispr Flow writes speaker mentions as <@speaker:2>.
    private var cleaned: String {
        text.replacingOccurrences(of: #"<@speaker:(\d+)>"#, with: "Speaker $1", options: .regularExpression)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = cleaned.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
            i += 1
            if line.isEmpty { out.append(.gap); continue }
            if line.hasPrefix("```") {
                var code: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                i += 1
                out.append(.code(code.joined(separator: "\n"))); continue
            }
            if line.hasPrefix("|") {
                var rows = [line]
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { rows.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1 }
                let cells = rows.filter { !$0.replacingOccurrences(of: "|", with: "").allSatisfy { "-: ".contains($0) } }
                    .map { $0.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) } }
                out.append(.table(cells)); continue
            }
            if line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { out.append(.rule); continue }
            if let m = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                out.append(.heading(line.distance(from: line.startIndex, to: m.upperBound) - 1, String(line[m.upperBound...]))); continue
            }
            if line.hasPrefix("> ") { out.append(.quote(String(line.dropFirst(2)))); continue }
            if let m = line.range(of: #"^[-*+] \[[ xX]\] "#, options: .regularExpression) {
                out.append(.check(indent, line[m].contains("[ ]") == false, String(line[m.upperBound...]))); continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { out.append(.bullet(indent, String(line.dropFirst(2)))); continue }
            if let m = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                out.append(.numbered(indent, String(line[..<m.upperBound].dropLast(2)), String(line[m.upperBound...]))); continue
            }
            out.append(.paragraph(line))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in view(b) }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }

    @ViewBuilder private func view(_ b: Block) -> some View {
        switch b {
        case .gap: Color.clear.frame(height: 2)
        case .rule: Divider().padding(.vertical, 4)
        case .heading(let level, let t):
            let size: CGFloat = [26, 22, 18, 16, 15, 14][min(level, 6) - 1]
            if level <= 2 { inline(t).font(Theme.serif(size)).padding(.top, 10) }
            else { inline(t).font(Theme.sans(size, .semibold)).padding(.top, 8) }
        case .bullet(let n, let t):
            HStack(alignment: .top, spacing: 8) { Text(n > 0 ? "◦" : "•").foregroundStyle(Theme.muted); inline(t) }.padding(.leading, CGFloat(n) * 18)
        case .numbered(let n, let num, let t):
            HStack(alignment: .top, spacing: 8) { Text(num + ".").font(Theme.sans(14)).foregroundStyle(Theme.muted).frame(minWidth: 18, alignment: .trailing); inline(t) }.padding(.leading, CGFloat(n) * 18)
        case .check(let n, let done, let t):
            HStack(alignment: .top, spacing: 8) {
                Icon(done ? "checkmark.square.fill" : "square", 16).foregroundStyle(Theme.muted).padding(.top, 2)
                inline(t).opacity(done ? 0.6 : 1)
            }.padding(.leading, CGFloat(n) * 18)
        case .quote(let t):
            HStack(spacing: 10) { RoundedRectangle(cornerRadius: 1.5).fill(Theme.muted.opacity(0.4)).frame(width: 3); inline(t).foregroundStyle(Theme.muted) }.fixedSize(horizontal: false, vertical: true)
        case .code(let c):
            Text(c).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.ink).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        case .table(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, cells in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                            inline(c).font(Theme.sans(13.5, r == 0 ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.vertical, 6)
                    Divider()
                }
            }
        case .paragraph(let t): inline(t)
        }
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
            .font(Theme.sans(14)).foregroundStyle(Theme.ink)
    }
}

struct NotetakerPage: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var nt = NotetakerController.shared
    @ObservedObject var player = MeetingPlayer.shared
    @LocalState private var question = ""
    @LocalState private var tab = 0
    @LocalState private var downloadedID: UUID?

    private var selected: Meeting? { store.meetings.first { $0.id == nt.selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Meetings", subtitle: "Records your mic and the call audio, then writes the notes.") {
                HStack(spacing: 10) {
                    Button { Router.shared.openSettings(.notetaker) } label: { Icon("gearshape", 18) }
                        .buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
                    recordButton
                }
            }
            if let w = nt.warning {
                HStack(alignment: .top, spacing: 8) {
                    Icon("exclamationmark.triangle.fill", 16).foregroundStyle(.orange)
                    Text(w).font(Theme.sans(13)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { nt.warning = nil } label: { Icon("xmark", 14) }.buttonStyle(.plain).pointer()
                }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }
            HStack(alignment: .top, spacing: 18) {
                main.frame(maxWidth: .infinity, maxHeight: .infinity)
                list.frame(width: 250)
            }
            askBar
        }
        .onChange(of: nt.selectedID) { _ in player.stop() }
    }

    private var recordButton: some View {
        Button { nt.toggle() } label: {
            HStack(spacing: 8) {
                switch nt.state {
                case .idle: Icon("record.circle", 16); Text("Start meeting")
                case .recording: Circle().fill(.red).frame(width: 8, height: 8); Text("Stop · \(NotetakerController.timestamp(nt.elapsed))")
                case .finishing: ProgressView().controlSize(.small); Text("Finishing…")
                }
            }
            .font(Theme.sans(13, .semibold)).foregroundStyle(nt.state == .idle ? Theme.ink : Theme.onInk)
            .padding(.horizontal, 16).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(nt.state == .idle ? Theme.button : Theme.ink))
        }.buttonStyle(.plain).pointer().disabled(nt.state == .finishing)
    }

    @ViewBuilder private var main: some View {
        if nt.state == .recording || nt.state == .finishing { live }
        else if let m = selected { detail(m) }
        else {
            VStack(spacing: 8) {
                Icon("waveform.badge.mic", 42).foregroundStyle(Theme.muted)
                Text("Start a meeting before a call").font(Theme.serif(22))
                Text("Rattle transcribes both sides on your Mac, then summarizes with your AI model.").font(Theme.sans(13.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(nt.state == .recording ? "Listening…" : "Wrapping up the transcript…").font(Theme.sans(14, .semibold))
                Text(nt.tapNote).font(Theme.sans(12)).foregroundStyle(Theme.muted)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if nt.liveLines.isEmpty { Text("Transcript appears here every ~20 seconds.").font(Theme.sans(13)).foregroundStyle(Theme.muted) }
                        ForEach(nt.liveLines) { TranscriptRow(line: $0).id($0.id) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: nt.liveLines.count) { _ in if let last = nt.liveLines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .padding(18).background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }

    private func detail(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: Binding(get: { m.title }, set: { v in if let i = store.meetings.firstIndex(where: { $0.id == m.id }) { store.meetings[i].title = v } }))
                .textFieldStyle(.plain).font(Theme.serif(26))
            HStack(spacing: 14) {
                Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
                Text("\(Int((m.duration / 60).rounded(.up))) min").font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
                if m.capturedSystemAudio { Label { Text("Call audio") } icon: { Icon("speaker.wave.2", 14) }.font(Theme.sans(12)).foregroundStyle(Theme.muted) }
                Spacer()
                Picker("", selection: $tab) { Text("Notes").tag(0); Text("Transcript").tag(1) }.pickerStyle(.segmented).frame(width: 170).labelsHidden()
                iconButton("doc.on.doc") { copy(tab == 0 ? (m.summary.isEmpty ? NotetakerController.transcriptText(m.lines) : m.summary) : NotetakerController.transcriptText(m.lines)) }
                iconButton("trash") { nt.delete(m.id) }
            }
            if m.audioURL != nil { playerBar(m) }
            ScrollView {
                if tab == 0 { notes(m) }
                else {
                    let seek: ((TimeInterval) -> Void)? = m.audioURL == nil ? nil : { t in player.play(m, from: t) }
                    VStack(alignment: .leading, spacing: 10) { ForEach(m.lines) { TranscriptRow(line: $0, onSeek: seek) } }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func playerBar(_ m: Meeting) -> some View {
        let active = player.meetingID == m.id
        let total = active ? player.duration : m.duration
        return HStack(spacing: 12) {
            Button { player.toggle(m) } label: {
                Icon(active && player.playing ? "pause.fill" : "play.fill", 14).foregroundStyle(Theme.onInk)
                    .frame(width: 30, height: 30).background(Circle().fill(Theme.ink))
            }.buttonStyle(.plain).pointer()
            Text(NotetakerController.timestamp(active ? player.time : 0)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
            Slider(value: Binding(get: { active ? player.time : 0 }, set: { t in if active { player.seek(to: t) } else { player.play(m, from: t) } }), in: 0...max(total, 1))
                .controlSize(.small).tint(Theme.ink)
            Text(NotetakerController.timestamp(total)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted)
            Button {
                guard nt.downloadAudio(m) != nil else { return }
                downloadedID = m.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if downloadedID == m.id { downloadedID = nil } }
            } label: {
                HStack(spacing: 6) {
                    Icon(downloadedID == m.id ? "checkmark" : "square.and.arrow.down", 15)
                    Text(downloadedID == m.id ? "Saved to Downloads" : "Download").font(Theme.sans(12.5, .medium))
                }.foregroundStyle(Theme.muted)
            }.buttonStyle(.plain).pointer().help("Save a copy of the recording to your Downloads folder")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }

    @ViewBuilder private func notes(_ m: Meeting) -> some View {
        if nt.summarizingID == m.id {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Writing notes…").font(Theme.sans(13)).foregroundStyle(Theme.muted) }.padding(.top, 8)
        } else if !m.summary.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                MarkdownLite(text: m.summary)
                PillButton(title: "Regenerate") { Task { await nt.summarize(m.id) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.summaryError ?? "No notes yet. Generate them from the transcript with your AI model.").font(Theme.sans(13.5)).foregroundStyle(Theme.muted)
                HStack {
                    PillButton(title: "Generate notes", prominent: true) { Task { await nt.summarize(m.id) } }
                    PillButton(title: "AI settings") { Router.shared.openSettings(.ai) }
                }
            }.padding(.top, 6)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(Theme.sans(12, .semibold)).foregroundStyle(Theme.muted).padding(.bottom, 4)
                if store.meetings.isEmpty { Text("Nothing recorded yet").font(Theme.sans(13)).foregroundStyle(Theme.muted) }
                ForEach(store.meetings) { m in
                    Button { nt.selectedID = m.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.title).font(Theme.sans(13.5, .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.sans(11.5)).foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(nt.selectedID == m.id && nt.state == .idle ? Theme.selected : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).pointer()
                }
            }
        }
        .padding(.leading, 16).overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var askBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nt.asking { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(Theme.sans(13)).foregroundStyle(Theme.muted) } }
            else if let a = nt.answer {
                ScrollView { MarkdownLite(text: a).padding(14) }.frame(maxHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    .overlay(alignment: .topTrailing) { Button { nt.answer = nil } label: { Icon("xmark", 12) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted).padding(8) }
            }
            HStack {
                TextField("What are my action items this week?", text: $question).textFieldStyle(.plain).font(Theme.sans(14))
                    .onSubmit { let q = question; question = ""; Task { await nt.ask(q) } }
                Button { let q = question; question = ""; Task { await nt.ask(q) } } label: { Icon("arrow.up.circle.fill", 28) }
                    .buttonStyle(.plain).pointer().foregroundStyle(question.isEmpty ? Theme.muted.opacity(0.5) : Theme.ink).disabled(question.isEmpty)
            }
            .padding(.horizontal, 18).frame(height: 46)
            .background(Capsule().fill(Theme.card))
        }
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Icon(name, 16) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
    }
    private func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
}

struct TranscriptRow: View {
    let line: TranscriptLine
    /// When set, the timestamp plays the recording from this line.
    var onSeek: ((TimeInterval) -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let onSeek {
                Button { onSeek(line.time) } label: { stamp.underline() }.buttonStyle(.plain).pointer().help("Play from here")
            } else { stamp }
            Text(line.speaker).font(Theme.sans(12.5, .semibold)).foregroundStyle(line.speaker == "You" ? Theme.ink : Color(red: 0.2, green: 0.4, blue: 0.7)).frame(width: 52, alignment: .leading)
            Text(line.text).font(Theme.sans(14)).foregroundStyle(Theme.ink).textSelection(.enabled)
        }
    }
    private var stamp: some View {
        Text(NotetakerController.timestamp(line.time)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted).frame(width: 44, alignment: .leading)
    }
}
