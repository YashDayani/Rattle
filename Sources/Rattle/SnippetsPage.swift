import SwiftUI

/// Dark, softly blurred hero used for empty states (Snippets, Dictionary).
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.07, green: 0.08, blue: 0.10)
            Circle().fill(Color(red: 0.16, green: 0.36, blue: 0.62)).frame(width: 340, height: 340).blur(radius: 70).offset(x: -90, y: -70)
            Circle().fill(Color(red: 0.80, green: 0.45, blue: 0.20)).frame(width: 300, height: 300).blur(radius: 80).offset(x: 520, y: 40)
            Circle().fill(Color(red: 0.34, green: 0.20, blue: 0.14)).frame(width: 260, height: 260).blur(radius: 70).offset(x: 260, y: 200)
            Color.black.opacity(0.28)
            content.padding(42)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct HeroHeadline: View {
    let before: String, italic: String, after: String
    var body: some View {
        (Text(before).font(Theme.serif(40)) + Text(italic).font(.system(size: 40, design: .serif).italic()) + Text(after).font(Theme.serif(40)))
            .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
    }
}

struct ExamplePill: View {
    let text: String
    var cue = false
    var body: some View {
        Text(text).font(cue ? .system(size: 17, weight: .medium).italic() : .system(size: 17))
            .foregroundStyle(cue ? Color.white : Theme.ink)
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 9).fill(cue ? Color.white.opacity(0.28) : Color.white.opacity(0.92)))
    }
}

struct SnippetsPage: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var editing: Snippet? = nil
    @LocalState private var isNew = false
    @LocalState private var query = ""
    @LocalState private var searching = false
    @LocalState private var alpha = false
    @LocalState private var spin = 0.0
    @LocalState private var flash: UUID? = nil

    private var shown: [Snippet] {
        var l = store.snippets
        if !query.isEmpty { l = l.filter { $0.trigger.localizedCaseInsensitiveContains(query) || $0.expansion.localizedCaseInsensitiveContains(query) } }
        if alpha { l.sort { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending } }
        return l
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Snippets").font(Theme.title())
                Spacer()
                PillButton(title: "Add new", prominent: true) { new() }
            }
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    TabBar(items: ["All"], selection: .constant(0), border: false).fixedSize()
                    if searching {
                        HStack(spacing: 8) {
                            Icon("magnifyingglass", 16).foregroundStyle(Theme.muted)
                            TextField("Search snippets", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                        }.padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Theme.card))
                    }
                    Spacer()
                    tool("magnifyingglass") { searching.toggle(); if !searching { query = "" } }
                    tool("arrow.up.arrow.down") { alpha.toggle() }.help(alpha ? "Sorted A–Z" : "Sorted by newest")
                    tool("arrow.clockwise") { withAnimation(.easeInOut(duration: 0.5)) { spin += 360 }; store.objectWillChange.send() }
                        .rotationEffect(.degrees(spin))
                }.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            ScrollView {
                if store.snippets.isEmpty { hero }
                else if shown.isEmpty { Text("No snippets match “\(query)”.").foregroundStyle(Theme.muted).padding(.top, 40).frame(maxWidth: .infinity) }
                else {
                    VStack(spacing: 10) { ForEach(shown) { row($0) } }
                }
            }
        }
        .sheet(item: $editing) { s in
            SnippetSheet(snippet: s, isNew: isNew) { saved in
                if let i = store.snippets.firstIndex(where: { $0.id == saved.id }) { store.snippets[i] = saved } else { store.snippets.insert(saved, at: 0) }
                editing = nil
            } cancel: { editing = nil }
        }
    }

    private var hero: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 14) {
                HeroHeadline(before: "The stuff ", italic: "you", after: " shouldn’t have to re-type.")
                Text("Save text you type often — an email, intro, or prompt — then say a word to drop it in instantly.")
                    .font(.system(size: 17)).foregroundStyle(.white.opacity(0.9)).padding(.bottom, 6)
                example("“my LinkedIn”", "https://www.linkedin.com/in/john-doe/")
                example("“rewrite prompt”", "Rewrite this to be more concise…")
                example("“intro email”", "Hey, would love to find some time to chat later…")
                Button { new() } label: {
                    Text("Add new snippet").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 20).frame(height: 48).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.95)))
                }.buttonStyle(.plain).pointer().padding(.top, 14)
            }
        }
    }

    private func example(_ cue: String, _ out: String) -> some View {
        HStack(spacing: 14) {
            ExamplePill(text: cue, cue: true)
            Icon("arrow.right", 15).foregroundStyle(.white.opacity(0.8))
            ExamplePill(text: out)
        }
    }

    private func row(_ s: Snippet) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text("“\(s.trigger)”").font(.system(size: 14.5, weight: .semibold).italic()).frame(width: 200, alignment: .leading).lineLimit(2)
            Icon("arrow.right", 14).foregroundStyle(Theme.muted).padding(.top, 3)
            Text(s.expansion).font(.system(size: 14)).foregroundStyle(Theme.ink.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            HStack(spacing: 12) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.expansion, forType: .string); flash = s.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flash = nil } } label: { Icon(flash == s.id ? "checkmark" : "doc.on.doc", 16) }
                Button { editing = s; isNew = false } label: { Icon("pencil", 16) }
                Button { store.snippets.removeAll { $0.id == s.id } } label: { Icon("trash", 16) }
            }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted).font(.system(size: 13))
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func tool(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Icon(icon, 19).foregroundStyle(Theme.muted).frame(width: 28, height: 28) }.buttonStyle(.plain).pointer()
    }

    private func new() { editing = Snippet(trigger: "", expansion: ""); isNew = true }
}

struct SnippetSheet: View {
    @LocalState private var trigger: String
    @LocalState private var expansion: String
    let id: UUID
    let isNew: Bool
    var save: (Snippet) -> Void
    var cancel: () -> Void

    init(snippet: Snippet, isNew: Bool, save: @escaping (Snippet) -> Void, cancel: @escaping () -> Void) {
        id = snippet.id; self.isNew = isNew; self.save = save; self.cancel = cancel
        _trigger = LocalState(wrappedValue: snippet.trigger); _expansion = LocalState(wrappedValue: snippet.expansion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add new snippet" : "Edit snippet").font(Theme.serif(26))
            Text("When you say").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField("e.g. my LinkedIn", text: $trigger).textFieldStyle(.roundedBorder)
            Text("Rattle types").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            TextEditor(text: $expansion).font(.system(size: 13)).frame(height: 120).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            HStack {
                Spacer()
                PillButton(title: "Cancel", action: cancel)
                PillButton(title: "Save", prominent: true) { save(Snippet(id: id, trigger: trigger.trimmingCharacters(in: .whitespaces), expansion: expansion)) }
                    .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
        }.padding(24).frame(width: 460)
    }
}
