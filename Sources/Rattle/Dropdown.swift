import SwiftUI
import Cocoa

/// Custom select control: a white 36pt trigger with a rotating chevron, and a floating menu the width of the trigger.
struct Dropdown<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]
    var width: CGFloat = 200
    @StateObject private var menu = DropdownMenuController()

    private var title: String { options.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Button { menu.open ? menu.close() : show() } label: {
            HStack(spacing: 4) {
                Text(title).font(Theme.sans(15)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Icon("chevron.down", 14).foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24).rotationEffect(.degrees(menu.open ? -180 : 0))
            }
            .padding(.leading, 8).padding(.trailing, 4).frame(width: width, height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointer()
        .background(DropdownAnchor(controller: menu))
        .animation(.easeOut(duration: 0.2), value: menu.open)
        .onDisappear { menu.close() }
    }

    private func show() {
        let values = options.map(\.value)
        menu.show(titles: options.map(\.title), selected: values.firstIndex(of: selection)) { i in selection = values[i] }
    }
}

/// Owns the floating menu panel for one Dropdown and closes it on any click or key press outside it.
@MainActor
final class DropdownMenuController: ObservableObject {
    @Published var open = false
    weak var anchor: NSView?
    private var panel: NSPanel?
    private var monitor: Any?

    func show(titles: [String], selected: Int?, pick: @escaping (Int) -> Void) {
        guard let anchor, let window = anchor.window else { return }
        let trigger = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let height = min(260, CGFloat(titles.count) * DropdownRow.height + 10)
        let floor = (window.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        let below = trigger.minY - 4 - height
        let y = below >= floor ? below : trigger.maxY + 4   // flip above the trigger when there is no room below

        let p = NSPanel(contentRect: NSRect(x: trigger.minX, y: y, width: trigger.width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.contentView = NSHostingView(rootView: DropdownMenu(titles: titles, selected: selected) { [weak self] i in
            pick(i); self?.close()
        })
        p.alphaValue = 0
        window.addChildWindow(p, ordered: .above)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.08; p.animator().alphaValue = 1 }
        panel = p
        open = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] e in
            guard let self, let panel = self.panel else { return e }
            if e.window === panel { return e }
            if e.type == .scrollWheel { self.close(); return e }
            self.close()
            if e.type == .keyDown { return e.keyCode == 53 ? nil : e }   // Esc only dismisses
            // A click on our own trigger just closes; swallow it so the button doesn't reopen the menu.
            if let a = self.anchor, e.window === a.window, a.bounds.contains(a.convert(e.locationInWindow, from: nil)) { return nil }
            return e
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
        if open { open = false }
    }
}

private struct DropdownAnchor: NSViewRepresentable {
    let controller: DropdownMenuController
    func makeNSView(context: Context) -> NSView { let v = NSView(); controller.anchor = v; return v }
    func updateNSView(_ v: NSView, context: Context) { controller.anchor = v }
}

private struct DropdownMenu: View {
    let titles: [String]
    let selected: Int?
    let pick: (Int) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { i in
                    DropdownRow(title: titles[i], selected: i == selected) { pick(i) }
                }
            }.padding(4)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
    }
}

private struct DropdownRow: View {
    static let height: CGFloat = 32
    let title: String
    let selected: Bool
    let action: () -> Void
    @LocalState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(Theme.sans(15, selected ? .semibold : .regular)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Icon("checkmark", 14).foregroundStyle(Theme.ink) }
            }
            .padding(.horizontal, 8).frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 4).fill(hover || selected ? Theme.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointer()
        .onHover { hover = $0 }
    }
}
