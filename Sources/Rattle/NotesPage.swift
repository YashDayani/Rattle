import SwiftUI
import Cocoa

/// Notes: a list of quick notes you can type or dictate into. Replaces the single Scratchpad box.
struct NotesPage: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var router = Router.shared
    private var openID: UUID? { get { router.openNoteID } nonmutating set { router.openNoteID = newValue } }
    @LocalState private var query = ""
    @LocalState private var searching = false
    @LocalState private var folderID: UUID? = nil
    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .top)]

    private var folder: Folder? { folderID.flatMap { id in store.folders.first { $0.id == id } } }

    /// Pinned notes first, then most recently edited. Searching looks in every folder.
    private var shown: [Note] {
        let sorted = store.notes.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
        if !query.isEmpty {
            return sorted.filter { $0.text.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
        }
        return sorted.filter { $0.folderID == folder?.id }
    }

    /// Folders only appear at the top level, and not while searching.
    private var shownFolders: [Folder] {
        folder == nil && query.isEmpty ? store.folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } : []
    }

    var body: some View {
        if let id = openID, let note = store.notes.first(where: { $0.id == id }) {
            NoteEditor(note: note, text: store.noteText(id), title: store.noteTitle(id), close: { close(id) },
                       pin: { togglePin(id) }, copy: { copy(note.text) }, delete: { openID = nil; remove(id) })
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: folder?.name ?? "Notes", subtitle: folder == nil ? "Quick notes you can type or dictate." : "Folder") {
                HStack(spacing: 8) {
                    if searching {
                        HStack(spacing: 8) {
                            Icon("magnifyingglass", 15).foregroundStyle(Theme.muted)
                            TextField("Search notes", text: $query).textFieldStyle(.plain).font(Theme.sans(14))
                        }.padding(.horizontal, 12).frame(width: 220, height: 34).background(Capsule().fill(Theme.card))
                    }
                    NoteTool(icon: "magnifyingglass", help: "Search") { searching.toggle(); if !searching { query = "" } }
                    NoteTool(icon: "arrow.up.left.and.arrow.down.right", help: "Open the small note window") { NotesWindow.shared.show() }
                    if let f = folder {
                        NoteTool(icon: "chevron.left", help: "Back to all notes") { folderID = nil }
                        NoteTool(icon: "pencil", help: "Rename folder") { rename(f) }
                        NoteTool(icon: "trash", help: "Delete folder (notes move out)", destructive: true) { removeFolder(f) }
                    } else {
                        PillButton(title: "New folder", prominent: false) { newFolder() }
                    }
                    PillButton(title: "New note", prominent: true) { new() }
                }
            }
            if store.notes.isEmpty && store.folders.isEmpty {
                empty(title: "No notes yet", detail: "Create one, then type or hold \(store.settings.shortcut.title) to dictate into it.")
            } else if shown.isEmpty && shownFolders.isEmpty {
                empty(title: query.isEmpty ? "This folder is empty" : "No notes match “\(query)”", detail: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shownFolders) { f in
                            FolderTile(folder: f, count: store.notes.filter { $0.folderID == f.id }.count,
                                       open: { folderID = f.id }, rename: { rename(f) }, delete: { removeFolder(f) },
                                       drop: { moveNote($0, to: f.id) })
                        }
                        ForEach(shown) { note in
                            NoteCard(note: note, folders: store.folders, open: { openID = note.id }, pin: { togglePin(note.id) },
                                     copy: { copy(note.text) }, delete: { remove(note.id) },
                                     move: { moveNote(note.id.uuidString, to: $0) })
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
        var note = Note()
        note.folderID = folder?.id
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

    private func newFolder() {
        guard let name = promptName(title: "New folder", initial: "") else { return }
        store.folders.append(Folder(name: name))
    }

    private func rename(_ f: Folder) {
        guard let name = promptName(title: "Rename folder", initial: f.name),
              let i = store.folders.firstIndex(where: { $0.id == f.id }) else { return }
        store.folders[i].name = name
    }

    /// Deleting a folder never deletes its notes; they go back to the top level.
    private func removeFolder(_ f: Folder) {
        for i in store.notes.indices where store.notes[i].folderID == f.id { store.notes[i].folderID = nil }
        store.folders.removeAll { $0.id == f.id }
        if folderID == f.id { folderID = nil }
    }

    @discardableResult
    private func moveNote(_ idString: String, to target: UUID?) -> Bool {
        guard let id = UUID(uuidString: idString), let i = store.notes.firstIndex(where: { $0.id == id }) else { return false }
        if store.notes[i].folderID != target { store.notes[i].folderID = target }
        return true
    }

    private func promptName(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

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

private struct FolderTile: View {
    let folder: Folder
    let count: Int
    var open: () -> Void
    var rename: () -> Void
    var delete: () -> Void
    var drop: (String) -> Bool
    @LocalState private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Icon("folder", 26).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Text(folder.name).font(Theme.sans(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text("\(count) note\(count == 1 ? "" : "s")").font(Theme.sans(12)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Theme.card : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Theme.ink.opacity(0.4) : Theme.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .dropDestination(for: String.self, action: { items, _ in items.first.map(drop) ?? false }, isTargeted: { targeted = $0 })
        .contextMenu {
            Button("Open", action: open)
            Button("Rename…", action: rename)
            Button("Delete folder", role: .destructive, action: delete)
        }
        .pointer()
    }
}

private struct NoteCard: View {
    let note: Note
    var folders: [Folder] = []
    var open: () -> Void
    var pin: () -> Void
    var copy: () -> Void
    var delete: () -> Void
    var move: (UUID?) -> Void = { _ in }
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
        .frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .draggable(note.id.uuidString)
        .contextMenu {
            Menu("Move to folder") {
                if note.folderID != nil { Button("Notes (no folder)") { move(nil) } }
                ForEach(folders.filter { $0.id != note.folderID }) { f in Button(f.name) { move(f.id) } }
                if folders.isEmpty { Text("No folders yet") }
            }
            Button(note.pinned ? "Unpin" : "Pin", action: pin)
            Button("Copy", action: copy)
            Button("Delete", role: .destructive, action: delete)
        }
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
    @Binding var title: String
    var close: () -> Void
    var pin: () -> Void
    var copy: () -> Void
    var delete: () -> Void
    @ObservedObject var store = AppStore.shared
    @LocalState private var preview = false
    @LocalState private var lastText = ""

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
                NoteTool(icon: preview ? "pencil" : "eye", help: preview ? "Edit Markdown (⌘E)" : "Preview Markdown (⌘E)") { preview.toggle() }
                    .keyboardShortcut("e", modifiers: .command)
                NoteTool(icon: note.pinned ? "pin.slash" : "pin", help: note.pinned ? "Unpin" : "Pin", action: pin)
                NoteTool(icon: "doc.on.doc", help: "Copy", action: copy)
                NoteTool(icon: "trash", help: "Delete", destructive: true, action: delete)
            }
            TextField(note.title == "New note" ? "Title" : note.title, text: $title)
                .textFieldStyle(.plain).font(Theme.serif(26)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
            if preview {
                ScrollView { MarkdownLite(text: text).padding(.horizontal, 12).padding(.bottom, 24) }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { preview = false }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
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
        }
        .onAppear { lastText = text; focusEditor() }
        // Pasting Markdown into an empty note flips to the rendered view; ⌘E (or double-click) edits the raw text.
        .onChange(of: text) { new in
            let wasEmpty = lastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if wasEmpty, new.count > 20, Note.looksLikeMarkdown(new) { preview = true }
            lastText = new
        }
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
