import SwiftUI
import Cocoa

/// Notes: a list of quick notes you can type or dictate into. Replaces the single Scratchpad box.
struct NotesPage: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var router = Router.shared
    private var openID: UUID? { get { router.openNoteID } nonmutating set { router.openNoteID = newValue } }
    @LocalState private var query = ""
    @LocalState private var searching = false

    /// Pinned notes first, then most recently edited.
    private var shown: [Note] {
        let sorted = store.notes.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
        return query.isEmpty ? sorted : sorted.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        if let id = openID, let note = store.notes.first(where: { $0.id == id }) {
            NoteEditor(note: note, text: store.noteText(id), close: { close(id) },
                       pin: { togglePin(id) }, copy: { copy(note.text) }, delete: { openID = nil; remove(id) })
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Notes", subtitle: "Quick notes you can type or dictate.") {
                HStack(spacing: 8) {
                    if searching {
                        HStack(spacing: 8) {
                            Icon("magnifyingglass", 15).foregroundStyle(Theme.muted)
                            TextField("Search notes", text: $query).textFieldStyle(.plain).font(Theme.sans(14))
                        }.padding(.horizontal, 12).frame(width: 220, height: 34).background(Capsule().fill(Theme.card))
                    }
                    NoteTool(icon: "magnifyingglass", help: "Search") { searching.toggle(); if !searching { query = "" } }
                    NoteTool(icon: "arrow.up.left.and.arrow.down.right", help: "Open the small note window") { NotesWindow.shared.show() }
                    PillButton(title: "New note", prominent: true) { new() }
                }
            }
            if store.notes.isEmpty {
                empty(title: "No notes yet", detail: "Create one, then type or hold \(store.settings.shortcut.title) to dictate into it.")
            } else if shown.isEmpty {
                empty(title: "No notes match “\(query)”", detail: nil)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(shown) { note in
                            NoteCard(note: note, open: { openID = note.id }, pin: { togglePin(note.id) },
                                     copy: { copy(note.text) }, delete: { remove(note.id) })
                        }
                    }
                    .padding(.horizontal, 2).padding(.top, 2).padding(.bottom, 24)   // room for the card shadows
                }
            }
        }
    }

    private func empty(title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
            if let detail { Text(detail).font(Theme.sans(15)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Actions

    private func new() {
        let note = Note()
        store.notes.insert(note, at: 0)
        searching = false; query = ""
        openID = note.id
    }

    /// Leaving the editor: a note left blank is discarded.
    private func close(_ id: UUID) {
        openID = nil
        if store.isBlankNote(id) { remove(id) }
    }

    private func remove(_ id: UUID) { store.notes.removeAll { $0.id == id } }

    private func togglePin(_ id: UUID) {
        if let i = store.notes.firstIndex(where: { $0.id == id }) { store.notes[i].pinned.toggle() }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

}

/// 28pt icon button used in the Notes header, the editor bar and on cards.
struct NoteTool: View {
    let icon: String
    var help: String = ""
    var destructive = false
    var action: () -> Void
    @LocalState private var hover = false
    var body: some View {
        Button(action: action) {
            Icon(icon, 16).foregroundStyle(hover ? (destructive ? Color.red : Theme.ink) : Theme.muted)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.card : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointer().help(help).onHover { hover = $0 }
    }
}

private struct NoteCard: View {
    let note: Note
    var open: () -> Void
    var pin: () -> Void
    var copy: () -> Void
    var delete: () -> Void
    @LocalState private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if note.pinned {
                Icon("pin", 14).foregroundStyle(Theme.muted).frame(width: 22, alignment: .leading).padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(note.title).font(Theme.sans(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview).font(Theme.sans(13)).lineSpacing(5).foregroundStyle(Theme.muted)
                        .lineLimit(3).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                HStack {
                    Text(note.updatedLabel)
                    Spacer()
                    Text("\(note.words) word\(note.words == 1 ? "" : "s")")
                }
                .font(Theme.sans(12)).foregroundStyle(Theme.muted.opacity(0.8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .overlay(alignment: .topTrailing) {
            // Actions float over the card's corner while the pointer is on it.
            HStack(spacing: 0) {
                NoteTool(icon: note.pinned ? "pin.slash" : "pin", help: note.pinned ? "Unpin" : "Pin", action: pin)
                Rectangle().fill(Theme.line).frame(width: 1, height: 28)
                NoteTool(icon: "doc.on.doc", help: "Copy", action: copy)
                Rectangle().fill(Theme.line).frame(width: 1, height: 28)
                NoteTool(icon: "trash", help: "Delete", destructive: true, action: delete)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .padding(8)
            .opacity(hover ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: hover)
        }
        .onHover { hover = $0 }
        .pointer()
    }
}

private struct NoteEditor: View {
    let note: Note
    @Binding var text: String
    var close: () -> Void
    var pin: () -> Void
    var copy: () -> Void
    var delete: () -> Void
    @ObservedObject var store = AppStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                Button(action: close) {
                    HStack(spacing: 2) {
                        Icon("chevron.left", 18)
                        Text("Notes").font(Theme.sans(15, .medium))
                    }
                    .foregroundStyle(Theme.ink).padding(.trailing, 8).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).pointer()
                Spacer()
                Text("Edited \(note.updatedLabel)").font(Theme.sans(12)).foregroundStyle(Theme.muted).padding(.trailing, 8)
                NoteTool(icon: note.pinned ? "pin.slash" : "pin", help: note.pinned ? "Unpin" : "Pin", action: pin)
                NoteTool(icon: "doc.on.doc", help: "Copy", action: copy)
                NoteTool(icon: "trash", help: "Delete", destructive: true, action: delete)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(Theme.sans(16)).lineSpacing(6).foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                if text.isEmpty {
                    // TextEditor insets its text by 5pt; the hint lines up with the caret.
                    HStack(spacing: 5) {
                        Text("Start typing, or hold")
                        Text(store.settings.shortcut.title).font(Theme.sans(12, .medium))
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.card))
                        Text("to dictate. The first line is the title.")
                    }
                    .font(Theme.sans(16)).foregroundStyle(Theme.switchOff)
                    .padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { focusEditor() }
    }

    /// Puts the caret in the editor so a new note is ready for typing or dictation straight away.
    private func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.keyWindow, let root = window.contentView else { return }
            func find(_ v: NSView) -> NSTextView? {
                if let t = v as? NSTextView, t.isEditable { return t }
                for s in v.subviews { if let t = find(s) { return t } }
                return nil
            }
            if let editor = find(root) { window.makeFirstResponder(editor) }
        }
    }
}
