import SwiftUI

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var page: HubPage = .dictation
    @Published var showSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var sidebarCollapsed = false
    @Published var isFullScreen = false
    func openSettings(_ tab: SettingsTab) { settingsTab = tab; showSettings = true }
}

/// Renders the small Markdown subset the summaries use (#, ##, bullets, checkboxes, bold).
struct MarkdownLite: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { Color.clear.frame(height: 2) }
                else if line.hasPrefix("## ") { Text(line.dropFirst(3)).font(Theme.serif(20)).foregroundStyle(Theme.ink).padding(.top, 10) }
                else if line.hasPrefix("# ") { Text(line.dropFirst(2)).font(Theme.serif(24)).foregroundStyle(Theme.ink) }
                else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                    HStack(alignment: .top, spacing: 8) {
                        Icon(line.hasPrefix("- [x]") ? "checkmark.square.fill" : "square", 16).foregroundStyle(Theme.muted).padding(.top, 2)
                        inline(String(line.dropFirst(6)))
                    }
                }
                else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) { Text("•").foregroundStyle(Theme.muted); inline(String(line.dropFirst(2))) }
                }
                else { inline(line) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
    private func inline(_ s: String) -> some View {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
            .font(.system(size: 14)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
    }
}

struct NotetakerPage: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var nt = NotetakerController.shared
    @LocalState private var question = ""
    @LocalState private var tab = 0

    private var selected: Meeting? { store.meetings.first { $0.id == nt.selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Notetaker", subtitle: "Records your mic and the call audio, then writes the notes.") {
                HStack(spacing: 10) {
                    Button { Router.shared.openSettings(.notetaker) } label: { Icon("gearshape", 18) }
                        .buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
                    recordButton
                }
            }
            if let w = nt.warning {
                HStack(alignment: .top, spacing: 8) {
                    Icon("exclamationmark.triangle.fill", 16).foregroundStyle(.orange)
                    Text(w).font(.system(size: 13)).foregroundStyle(Theme.ink)
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
    }

    private var recordButton: some View {
        Button { nt.toggle() } label: {
            HStack(spacing: 8) {
                switch nt.state {
                case .idle: Icon("record.circle", 16); Text("Start Notetaker")
                case .recording: Circle().fill(.red).frame(width: 8, height: 8); Text("Stop · \(NotetakerController.timestamp(nt.elapsed))")
                case .finishing: ProgressView().controlSize(.small); Text("Finishing…")
                }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(nt.state == .idle ? Theme.ink : .white)
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
                Text("Start Notetaker before a call").font(Theme.serif(22))
                Text("Rattle transcribes both sides on your Mac, then summarizes with your AI model.").font(.system(size: 13.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(nt.state == .recording ? "Listening…" : "Wrapping up the transcript…").font(.system(size: 14, weight: .semibold))
                Text(nt.tapNote).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if nt.liveLines.isEmpty { Text("Transcript appears here every ~20 seconds.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
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
                Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                Text("\(Int((m.duration / 60).rounded(.up))) min").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                if m.capturedSystemAudio { Label { Text("Call audio") } icon: { Icon("speaker.wave.2", 14) }.font(.system(size: 12)).foregroundStyle(Theme.muted) }
                Spacer()
                Picker("", selection: $tab) { Text("Notes").tag(0); Text("Transcript").tag(1) }.pickerStyle(.segmented).frame(width: 170).labelsHidden()
                iconButton("doc.on.doc") { copy(tab == 0 ? (m.summary.isEmpty ? NotetakerController.transcriptText(m.lines) : m.summary) : NotetakerController.transcriptText(m.lines)) }
                iconButton("trash") { store.meetings.removeAll { $0.id == m.id }; nt.selectedID = nil }
            }
            ScrollView {
                if tab == 0 { notes(m) }
                else {
                    VStack(alignment: .leading, spacing: 10) { ForEach(m.lines) { TranscriptRow(line: $0) } }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func notes(_ m: Meeting) -> some View {
        if nt.summarizingID == m.id {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Writing notes…").font(.system(size: 13)).foregroundStyle(Theme.muted) }.padding(.top, 8)
        } else if !m.summary.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                MarkdownLite(text: m.summary)
                PillButton(title: "Regenerate") { Task { await nt.summarize(m.id) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.summaryError ?? "No notes yet. Generate them from the transcript with your AI model.").font(.system(size: 13.5)).foregroundStyle(Theme.muted)
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
                Text("Notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.bottom, 4)
                if store.meetings.isEmpty { Text("Nothing recorded yet").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                ForEach(store.meetings) { m in
                    Button { nt.selectedID = m.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.title).font(.system(size: 13.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
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
            if nt.asking { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.system(size: 13)).foregroundStyle(Theme.muted) } }
            else if let a = nt.answer {
                ScrollView { MarkdownLite(text: a).padding(14) }.frame(maxHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    .overlay(alignment: .topTrailing) { Button { nt.answer = nil } label: { Icon("xmark", 12) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted).padding(8) }
            }
            HStack {
                TextField("What are my action items this week?", text: $question).textFieldStyle(.plain).font(.system(size: 14))
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
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(NotetakerController.timestamp(line.time)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.muted).frame(width: 44, alignment: .leading)
            Text(line.speaker).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(line.speaker == "You" ? Theme.ink : Color(red: 0.2, green: 0.4, blue: 0.7)).frame(width: 52, alignment: .leading)
            Text(line.text).font(.system(size: 14)).foregroundStyle(Theme.ink).textSelection(.enabled)
        }
    }
}
