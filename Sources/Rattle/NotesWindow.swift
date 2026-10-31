import SwiftUI
import Cocoa

extension AppStore {
    /// Text of one note, looked up by id on every read and write so it stays valid while the list reorders.
    func noteText(_ id: UUID) -> Binding<String> {
        Binding(get: { self.notes.first { $0.id == id }?.text ?? "" },
                set: { value in
                    guard let i = self.notes.firstIndex(where: { $0.id == id }), self.notes[i].text != value else { return }
                    self.notes[i].text = value
                    self.notes[i].updated = Date()
                })
    }

    /// The note's explicit title; empty means "use the first line".
    func noteTitle(_ id: UUID) -> Binding<String> {
        Binding(get: { self.notes.first { $0.id == id }?.customTitle ?? "" },
                set: { value in
                    guard let i = self.notes.firstIndex(where: { $0.id == id }) else { return }
                    let v: String? = value.isEmpty ? nil : value
                    guard self.notes[i].customTitle != v else { return }
                    self.notes[i].customTitle = v
                    self.notes[i].updated = Date()
                })
    }

    func isBlankNote(_ id: UUID) -> Bool {
        notes.first { $0.id == id }?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

/// State of the small floating note window: which notes are open as tabs, and its panel options.
@MainActor
final class NotesWindowModel: ObservableObject {
    static let shared = NotesWindowModel()
    @Published var tabs: [UUID] = []
    @Published var active: UUID?
    @Published var sidebarOpen = false
    @Published var searching = false
    @Published var query = ""
    @Published var fontSize: CGFloat = 14
    @Published var busy = false
    @Published var message: String?
    /// Text from before the last transform, so it can be put back.
    @Published var undo: (id: UUID, text: String)?
    private var store: AppStore { .shared }

    /// Drops tabs whose note was deleted elsewhere, and makes sure there is a note to write in.
    func prepare() {
        tabs.removeAll { id in !store.notes.contains { $0.id == id } }
        if let a = active, !tabs.contains(a) { active = tabs.last }
        if active == nil { active = tabs.last }
        if active == nil { newNote() }
    }

    func newNote() {
        let note = Note()
        store.notes.insert(note, at: 0)
        tabs.append(note.id)
        active = note.id
    }

    func open(_ id: UUID) {
        if !tabs.contains(id) { tabs.append(id) }
        active = id
    }

    func close(_ id: UUID) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        discardIfBlank(id)
        if active == id { active = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)] }
        if tabs.isEmpty { NotesWindow.shared.close() }
    }

    /// Notes left blank are thrown away when the window closes.
    func windowClosed() {
        for id in tabs { discardIfBlank(id) }
        tabs.removeAll { id in !store.notes.contains { $0.id == id } }
        if let a = active, !tabs.contains(a) { active = tabs.last }
        message = nil; undo = nil
    }

    private func discardIfBlank(_ id: UUID) {
        if store.isBlankNote(id) { store.notes.removeAll { $0.id == id } }
    }

    func cycleFontSize() { fontSize = fontSize >= 18 ? 14 : fontSize + 2 }

    func copyActive() -> Bool {
        guard let id = active, !store.isBlankNote(id), let text = store.notes.first(where: { $0.id == id })?.text else { return false }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    /// Shows the list of transforms at the pointer and runs the chosen one on the open note.
    func chooseTransform() {
        let menu = NSMenu()
        for t in store.allTransforms { menu.addItem(ActionMenuItem(title: t.name) { [weak self] in self?.run(t) }) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func run(_ t: Transform) {
        guard !busy, let id = active, !store.isBlankNote(id), let original = store.notes.first(where: { $0.id == id })?.text else {
            message = "Write something first"; return
        }
        busy = true; message = nil
        let settings = store.settings
        Task {
            do {
                let result = try await Transforms.run(t, on: original, settings: settings)
                store.noteText(id).wrappedValue = result
                undo = (id, original)
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }

    func undoTransform() {
        guard let u = undo else { return }
        store.noteText(u.id).wrappedValue = u.text
        undo = nil
    }

    /// Opens the note in the main window's Notes page and closes this one.
    func expand() {
        Router.shared.openNoteID = active.flatMap { store.isBlankNote($0) ? nil : $0 }
        Router.shared.page = .notes
        NotesWindow.shared.close()
        (NSApp.delegate as? AppDelegate)?.showHub()
    }
}

/// NSMenuItem that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

/// The small note window: icon rail on the left, open notes as tabs along the top, the editor in a rounded panel.
struct NotesWindowView: View {
    @ObservedObject var model = NotesWindowModel.shared
    @ObservedObject var store = AppStore.shared
    @LocalState private var copied = false

    private static let rail: CGFloat = 48
    private static let listWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                sidebar
                editorPanel
            }
        }
        .background(Theme.window)
        .animation(Theme.Motion.quick, value: model.sidebarOpen)
        .onReceive(model.$active) { _ in NotesWindow.shared.focusEditor() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            AppIconView(size: 18).frame(width: Self.rail)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { ForEach(model.tabs, id: \.self) { tab($0) } }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: CGFloat(model.tabs.count) * 170, alignment: .leading)
            BarButton(icon: "plus", help: "New note") { model.newNote() }
            Spacer(minLength: 8)
            BarButton(icon: "arrow.up.left.and.arrow.down.right", help: "Open in Rattle") { model.expand() }
            BarButton(icon: "xmark", help: "Close") { NotesWindow.shared.close() }
        }
        .padding(.vertical, 8).padding(.trailing, 12)
    }

    private func tab(_ id: UUID) -> some View {
        let on = model.active == id
        let title = store.isBlankNote(id) ? "Untitled" : (store.notes.first { $0.id == id }?.title ?? "Untitled")
        return NoteTab(title: title, active: on, underline: on && model.tabs.count > 1,
                       select: { model.active = id }, close: { model.close(id) })
    }

    // MARK: Sidebar (icon rail; widens to show labels and the list of notes)

    private var sidebar: some View {
        let open = model.sidebarOpen
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                RailButton(icon: "sidebar.left", title: "Notes", open: open) { model.sidebarOpen.toggle(); if !model.sidebarOpen { model.searching = false; model.query = "" } }
                RailButton(icon: "square.and.pencil", title: "New note", open: open) { model.newNote() }
                RailButton(icon: "magnifyingglass", title: "Search", open: open) {
                    if open && model.searching { model.searching = false; model.query = "" } else { model.sidebarOpen = true; model.searching = true }
                }
            }.padding(.top, 8)
            if open { noteList } else { Spacer(minLength: 0) }
            VStack(spacing: 0) {
                RailButton(icon: "sparkles", title: "Transform", open: open) { model.chooseTransform() }
                RailButton(icon: "textformat.size", title: "Text size", open: open) { model.cycleFontSize() }
            }.padding(.vertical, 4)
        }
        .frame(width: Self.rail + (open ? Self.listWidth : 0), alignment: .leading)
        .clipped()
    }

    private var listed: [Note] {
        let sorted = store.notes.sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
        return model.query.isEmpty ? sorted : sorted.filter { $0.text.localizedCaseInsensitiveContains(model.query) }
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            if model.searching {
                HStack(spacing: 6) {
                    Icon("magnifyingglass", 13).foregroundStyle(Theme.muted)
                    TextField("Search", text: $model.query).textFieldStyle(.plain).font(Theme.sans(12))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.line))
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 6)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 8).padding(.bottom, 10).padding(.top, 4)
            ScrollView {
                VStack(spacing: 2) {
                    if listed.isEmpty {
                        Text(model.query.isEmpty ? "No notes yet" : "No matches").font(Theme.sans(12)).foregroundStyle(Theme.muted).padding(.vertical, 16)
                    }
                    ForEach(listed) { note in
                        NoteListRow(title: store.isBlankNote(note.id) ? "Untitled" : note.title, detail: note.updatedLabel,
                                    pinned: note.pinned, active: model.active == note.id) { model.open(note.id) }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
        .frame(width: Self.rail + Self.listWidth)
    }

    // MARK: Editor

    private var editorPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.page)
            if let id = model.active {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: store.noteText(id))
                        .font(Theme.sans(model.fontSize)).lineSpacing(model.fontSize * 0.4).foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .id(id)
                    if store.isBlankNote(id) {
                        // TextEditor insets its text by 5pt; the hint lines up with the caret.
                        Text("Type, or hold \(store.settings.pushTitle) to dictate")
                            .font(Theme.sans(model.fontSize)).foregroundStyle(Theme.switchOff)
                            .padding(.leading, 5).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 50)
            }
            overlays.padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .padding(.trailing, 8).padding(.bottom, 8)
    }

    private var overlays: some View {
        HStack(spacing: 8) {
            if model.busy {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Transforming…").font(Theme.sans(12)).foregroundStyle(Theme.muted) }
            } else if let m = model.message {
                Text(m).font(Theme.sans(12)).foregroundStyle(Theme.muted).lineLimit(2).frame(maxWidth: 240, alignment: .trailing)
            }
            if model.undo != nil, model.undo?.id == model.active, !model.busy {
                NotePill(icon: "arrow.uturn.backward", title: "Undo", prominent: false) { model.undoTransform() }
            }
            NotePill(icon: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy", prominent: true) {
                guard model.copyActive() else { return }
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
        }
    }
}

// MARK: - Pieces

/// 28pt icon button in the window's top bar.
private struct BarButton: View {
    let icon: String
    let help: String
    var action: () -> Void
    @LocalState private var hover = false
    var body: some View {
        Button(action: action) {
            Icon(icon, 16).foregroundStyle(Theme.ink).frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(hover ? Theme.selected : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(.press).pointer().tip(help).onHover { hover = $0 }
    }
}

/// Full-width 36pt row in the icon rail; shows its label once the sidebar is open.
private struct RailButton: View {
    let icon: String
    let title: String
    let open: Bool
    var action: () -> Void
    @LocalState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Icon(icon, 18).frame(width: 48)
                if open { Text(title).font(Theme.sans(13, .medium)).lineLimit(1).padding(.trailing, 8) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink).frame(height: 36)
            .background(hover ? Theme.selected : .clear)
            .contentShape(Rectangle())
        }.buttonStyle(.press).pointer().tip(open ? "" : title, edge: .trailing).onHover { hover = $0 }
    }
}

private struct NoteTab: View {
    let title: String
    let active: Bool
    let underline: Bool
    var select: () -> Void
    var close: () -> Void
    @LocalState private var hover = false
    @LocalState private var closeHover = false
    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(Theme.sans(12, active ? .semibold : .medium)).lineLimit(1).truncationMode(.tail).frame(maxWidth: 120)
            Button(action: close) {
                Icon("xmark", 10).frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(closeHover ? Theme.selected : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press).pointer().onHover { closeHover = $0 }
            .opacity(active || hover ? 1 : 0)
        }
        .foregroundStyle(active || hover ? Theme.ink : Theme.muted)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .overlay(alignment: .bottom) { if underline { Rectangle().fill(Theme.ink).frame(height: 2) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
        .pointer()
    }
}

private struct NoteListRow: View {
    let title: String
    let detail: String
    let pinned: Bool
    let active: Bool
    var action: () -> Void
    @LocalState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 2) {
                if pinned { Icon("pin", 11).foregroundStyle(Theme.muted).padding(.top, 2).padding(.trailing, 4) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.sans(12, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(Theme.sans(11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(active ? Theme.selected : (hover ? Theme.selected.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }.buttonStyle(.press).pointer().onHover { hover = $0 }
    }
}

/// Pill button floating over the editor's bottom-right corner.
private struct NotePill: View {
    let icon: String
    let title: String
    let prominent: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(icon, 14)
                Text(title).font(Theme.sans(13, .medium))
            }
            .foregroundStyle(prominent ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(prominent ? Theme.ink : Theme.button))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .contentShape(Capsule())
        }.buttonStyle(.press).pointer()
    }
}

// MARK: - Window

/// A panel that can take keyboard focus, so you can type and dictate into it.
private final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotesWindow: NSObject, NSWindowDelegate {
    static let shared = NotesWindow()
    private var panel: NSPanel?

    func show() {
        NotesWindowModel.shared.prepare()
        if panel == nil {
            let p = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
                               styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { p.standardWindowButton(b)?.isHidden = true }
            p.isMovableByWindowBackground = true
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.minSize = NSSize(width: 380, height: 300)
            p.backgroundColor = NSColor(Theme.window)
            p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: NotesWindowView())
            host.sizingOptions = []
            host.safeAreaRegions = []       // the view draws its own top bar under the hidden title bar
            p.contentView = host
            p.delegate = self
            p.center()
            p.setFrameAutosaveName("RattleNotes")
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusEditor()
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) { NotesWindowModel.shared.windowClosed() }

    /// Puts the caret in the editor so the note is ready for typing or dictation.
    func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let window = self?.panel, window.isVisible, let root = window.contentView else { return }
            func find(_ v: NSView) -> NSTextView? {
                if let t = v as? NSTextView, t.isEditable { return t }
                for s in v.subviews { if let t = find(s) { return t } }
                return nil
            }
            if let editor = find(root), window.firstResponder !== editor { window.makeFirstResponder(editor) }
        }
    }
}
