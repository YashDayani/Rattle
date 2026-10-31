import Cocoa

/// Inserts text into whatever app has focus: pasteboard + synthesized ⌘V, then restores the clipboard.
enum TextInserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pb.clearContents()
            for item in saved {
                let n = NSPasteboardItem()
                for (t, d) in item { n.setData(d, forType: t) }
                pb.writeObjects([n])
            }
        }
    }
}

extension TextInserter {
    /// Presses Return in the frontmost app, for the "Press Enter" shortcut.
    static func pressReturn() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
        down?.flags = []; up?.flags = []
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

extension TextInserter {
    /// Returns the frontmost app's selected text by issuing ⌘C, then restores the clipboard.
    @MainActor
    static func captureSelection() async -> String? {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        let before = pb.changeCount
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap); up?.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 160_000_000)
        let text = pb.changeCount != before ? pb.string(forType: .string) : nil
        pb.clearContents()
        for item in saved {
            let n = NSPasteboardItem()
            for (t, d) in item { n.setData(d, forType: t) }
            pb.writeObjects([n])
        }
        return (text?.isEmpty ?? true) ? nil : text
    }
}
