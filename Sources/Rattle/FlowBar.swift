import SwiftUI
import Cocoa

/// The floating pill at the bottom of the screen (Rattle's "Flow Bar").
struct FlowBarView: View {
    @ObservedObject var dictation = DictationController.shared
    @LocalState private var dots = 0
    private let tick = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(fill)).overlay(Capsule().stroke(Color(red: 0.188, green: 0.188, blue: 0.184), lineWidth: 1.5))
            content
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(active ? 0.28 : 0), radius: 8, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: dictation.phase)
        .frame(width: 320, height: 64, alignment: .bottom)
        .padding(.bottom, 4)
    }

    private var active: Bool { dictation.phase != .idle }
    private var fill: Double { active ? 0.92 : 0.55 }
    private var height: CGFloat { active ? 30 : 9 }
    private var width: CGFloat {
        switch dictation.phase {
        case .idle: return 46
        case .listening(let hf): return hf ? 150 : 112
        case .processing: return 76
        case .message(let m): return min(300, CGFloat(m.count) * 6.4 + 36)
        }
    }

    @ViewBuilder private var content: some View {
        switch dictation.phase {
        case .idle: EmptyView()
        case .listening(let hf):
            HStack(spacing: 8) {
                if hf { Icon("hands.sparkles.fill", 12).foregroundStyle(.white.opacity(0.85)) }
                HStack(spacing: 2.5) {
                    ForEach(0..<dictation.levels.count, id: \.self) { i in
                        Capsule().fill(.white)
                            .frame(width: 2.5, height: 4 + CGFloat(dictation.levels[i]) * 18)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: dictation.levels)
            }
        case .processing:
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.white.opacity(i == dots % 3 ? 1 : 0.35)).frame(width: 5, height: 5)
                }
            }.onReceive(tick) { _ in dots += 1 }
        case .message(let m):
            Text(m).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 12)
        }
    }
}

@MainActor
final class FlowBarWindow {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: FlowBarView())
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - 160, y: f.minY + 2))
    }

    func setVisible(_ v: Bool) { v ? panel.orderFrontRegardless() : panel.orderOut(nil) }
}
