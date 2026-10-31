import SwiftUI
import Cocoa

/// Listens for the next key combination while a shortcut field is being edited.
///
/// A combination with a letter, number, symbol key or mouse button is taken the moment that key goes down. One made only
/// of modifiers (fn, ⌃ + ⌥) is taken when everything is released. Esc on its own backs out.
@MainActor
final class ShortcutRecorder: ObservableObject {
    struct Target: Equatable { let action: ShortcutAction; let index: Int }

    @Published private(set) var target: Target?
    @Published private(set) var held: [Int] = []
    @Published var error: String?
    /// Receives the finished chord; returns why it was refused, or nil once it was saved.
    var commit: ((Target, KeyChord) -> String?)?

    private var down: Set<Int> = []
    private var peak: [Int] = []
    private var monitor: Any?

    func start(_ next: Target) {
        stop()
        target = next
        DictationController.shared.setShortcutsSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown { self.stop(); return event }   // a click elsewhere cancels, and still lands
            self.handle(event)
            return nil   // keep the keys away from the rest of the app while listening
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if target != nil { DictationController.shared.setShortcutsSuspended(false) }
        target = nil; down = []; peak = []; held = []
    }

    private static func flag(for code: Int) -> NSEvent.ModifierFlags? {
        switch code {
        case 63: return .function
        case 58, 61: return .option
        case 54, 55: return .command
        case 59, 62: return .control
        case 56, 60: return .shift
        default: return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let isMouse = event.type == .otherMouseDown || event.type == .otherMouseUp
        let code = isMouse ? KeyChord.mouseCode(button: event.buttonNumber) : Int(event.keyCode)
        let isDown: Bool
        switch event.type {
        case .flagsChanged:
            guard let flag = Self.flag(for: code) else { return }
            isDown = event.modifierFlags.contains(flag)
        case .keyDown:
            if event.isARepeat { return }
            isDown = true
        case .otherMouseDown:
            isDown = true
        default:
            isDown = false
        }

        if isDown {
            down.insert(code)
            if !peak.contains(code) { peak.append(code) }
            held = KeyChord(peak).keys
            error = nil
            if !KeyChord.modifierCodes.contains(code) { finish() }
        } else {
            down.remove(code)
            if down.isEmpty && !peak.isEmpty { finish() }
        }
    }

    private func finish() {
        guard let target else { return }
        let chord = KeyChord(peak)
        if chord.keys == [53] && target.action != .cancel { stop(); return }   // Esc backs out of recording
        if let problem = commit?(target, chord) {
            error = problem
            peak = Array(down)   // keep listening; whatever is still held counts toward the next try
            held = KeyChord(peak).keys
        } else {
            stop()
        }
    }
}

/// One key as a small rounded cap.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A chord drawn as key caps.
struct ChordCaps: View {
    let chord: KeyChord
    var body: some View {
        HStack(spacing: 6) { ForEach(chord.parts, id: \.self) { KeyCap(text: $0) } }
    }
}

struct ShortcutsTab: View {
    @ObservedObject var store = AppStore.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your preferred shortcuts for using Rattle.").font(Theme.sans(15)).foregroundStyle(Theme.muted)
            ForEach(ShortcutAction.allCases) { action in
                ShortcutRow(action: action, recorder: recorder)
            }
            HStack {
                PillButton(title: "Reset to default") {
                    recorder.stop()
                    store.settings.bindings = .default
                    DictationController.shared.applyShortcut()
                }
                Spacer()
            }.padding(.top, 4)
        }
        .onAppear {
            recorder.commit = { target, chord in
                var bindings = store.settings.bindings
                let existing = bindings[target.action]
                let replacing = target.index < existing.count ? existing[target.index] : nil
                if let problem = bindings.problem(with: chord, for: target.action, replacing: replacing) { return problem }
                if let replacing, let at = existing.firstIndex(of: replacing) { bindings[target.action][at] = chord }
                else { bindings[target.action].append(chord) }
                store.settings.bindings = bindings
                DictationController.shared.applyShortcut()
                return nil
            }
        }
        .onDisappear { recorder.stop() }
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var recorder: ShortcutRecorder
    @ObservedObject var store = AppStore.shared

    private var chords: [KeyChord] { store.settings.bindings[action] }
    /// An empty action still shows one blank field to click.
    private var slots: Int { max(1, chords.count) }
    private var detail: String {
        action == .commandMode && !store.settings.commandModeEnabled ? "\(action.detail). Currently off in Transforms." : action.detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.sans(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(0..<slots, id: \.self) { index in
                    HStack(spacing: 8) {
                        field(index)
                        if index == slots - 1 && !chords.isEmpty && chords.count < ShortcutBindings.maxPerAction { addButton }
                    }
                }
                if let error = recorder.error, recorder.target?.action == action {
                    Text(error).font(Theme.sans(13)).foregroundStyle(Theme.warn).multilineTextAlignment(.trailing).frame(width: 300, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.card))
    }

    private func field(_ index: Int) -> some View {
        let chord: KeyChord? = index < chords.count ? chords[index] : nil
        let isRecording = recorder.target == .init(action: action, index: index)
        // The first push-to-talk shortcut can be changed but not removed: dictation needs one.
        let canDelete = chord != nil && !(action == .pushToTalk && chords.count == 1)
        return HStack(spacing: 8) {
            Button { recorder.start(.init(action: action, index: index)) } label: {
                HStack(spacing: 8) {
                    if isRecording {
                        if recorder.held.isEmpty { Text("Press the shortcut…").font(Theme.sans(15)).foregroundStyle(Theme.muted) }
                        else { ChordCaps(chord: KeyChord(recorder.held)) }
                    } else if let chord { ChordCaps(chord: chord) }
                    else { Text("Click to add a shortcut").font(Theme.sans(15)).foregroundStyle(Theme.muted) }
                    Spacer(minLength: 0)
                    Icon("pencil", 16).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 10).frame(width: canDelete ? 262 : 300, height: 46)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(isRecording ? Theme.ink : Theme.line, lineWidth: isRecording ? 1.5 : 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).pointer()
            .accessibilityLabel(chord.map { "\(action.title): \($0.title). Change" } ?? "\(action.title): add a shortcut")

            if canDelete, let chord {
                Button {
                    recorder.stop()
                    store.settings.bindings[action].removeAll { $0 == chord }
                    DictationController.shared.applyShortcut()
                } label: { Icon("trash", 16).foregroundStyle(Theme.ink).frame(width: 30, height: 46) }
                    .buttonStyle(.press).pointer().accessibilityLabel("Remove \(action.title) shortcut \(chord.title)")
            }
        }
    }

    private var addButton: some View {
        Button { recorder.start(.init(action: action, index: chords.count)) } label: {
            Icon("plus", 18).foregroundStyle(Theme.muted).frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.button))
        }.buttonStyle(.press).pointer().accessibilityLabel("Add another shortcut for \(action.title)")
    }
}
