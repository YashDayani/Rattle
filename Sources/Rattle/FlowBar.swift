import SwiftUI
import Cocoa

/// What the pointer is over in the open Flow Bar.
enum FlowBarTarget: Equatable { case dictate, notetaker, notetakerPage, notes, transforms, transformsPage }

/// Geometry shared by the SwiftUI drawing and the AppKit hit-testing. All x values are from the panel's left edge.
/// On hover the resting pill itself grows into the mic bubble, and the other controls open beside it on the same row.
/// Notetaker and Transforms are circles that widen into a pill with a caret while hovered, so the slots to their
/// right depend on which control is currently hovered.
enum FlowBarLayout {
    static let panel = CGSize(width: 560, height: 104)
    static let bottomInset: CGFloat = 4
    static let pillHeight: CGFloat = 8
    static let height: CGFloat = 30                     // height of the control row
    static let control: CGFloat = 30                    // a round control
    static let wide: CGFloat = 54                       // the mic bubble, and a control widened by hover
    static let gap: CGFloat = 8                         // between every pair of controls
    static var centerX: CGFloat { panel.width / 2 }

    /// Bottom of the control row, measured from the bottom of the panel.
    static var rowMinY: CGFloat { bottomInset }
    // Centres measured from the top of the panel (SwiftUI coordinates).
    static var pillMidY: CGFloat { panel.height - bottomInset - pillHeight / 2 }
    static var rowMidY: CGFloat { panel.height - rowMinY - height / 2 }
    static var tooltipMidY: CGFloat { rowMidY - height / 2 - 10 - 18 }

    static func notetakerWidth(_ hovered: FlowBarTarget?) -> CGFloat { hovered == .notetaker || hovered == .notetakerPage ? wide : control }
    static func transformsWidth(_ hovered: FlowBarTarget?) -> CGFloat { hovered == .transforms || hovered == .transformsPage ? wide : control }
    static var dictateMinX: CGFloat { centerX - wide / 2 }
    static var notetakerMinX: CGFloat { centerX + wide / 2 + gap }
    static func notesMinX(_ hovered: FlowBarTarget?) -> CGFloat { notetakerMinX + notetakerWidth(hovered) + gap }
    static func transformsMinX(_ hovered: FlowBarTarget?) -> CGFloat { notesMinX(hovered) + control + gap }

    /// Pointer zones, measured from the bottom of the panel (AppKit coordinates).
    static var restZone: CGRect { CGRect(x: centerX - 40, y: 0, width: 80, height: 20) }
    static var openZone: CGRect {
        let maxX = notetakerMinX + wide + gap + control + gap + wide      // widest the row can get
        return CGRect(x: dictateMinX - 12, y: 0, width: maxX - dictateMinX + 24, height: rowMinY + height + 12)
    }

    /// The control under `p`, given which control is currently widened.
    static func target(at p: CGPoint, hovered: FlowBarTarget?) -> FlowBarTarget? {
        guard p.y >= rowMinY, p.y <= rowMinY + height else { return nil }
        func hit(_ minX: CGFloat, _ width: CGFloat) -> Bool { p.x >= minX && p.x <= minX + width }
        if hit(dictateMinX, wide) { return .dictate }
        if hit(notetakerMinX, control) { return .notetaker }
        if notetakerWidth(hovered) > control, hit(notetakerMinX + control, wide - control) { return .notetakerPage }
        if hit(notesMinX(hovered), control) { return .notes }
        let t = transformsMinX(hovered)
        if hit(t, control) { return .transforms }
        if transformsWidth(hovered) > control, hit(t + control, wide - control) { return .transformsPage }
        return nil
    }

    static func midX(of t: FlowBarTarget) -> CGFloat {
        switch t {
        case .dictate: return centerX
        case .notetaker, .notetakerPage: return notetakerMinX + wide / 2
        case .notes: return notesMinX(t) + control / 2
        case .transforms, .transformsPage: return transformsMinX(t) + wide / 2
        }
    }
}

/// Hover state of the Flow Bar. Driven by FlowBarTrackingView, because SwiftUI hover does not fire while another app is frontmost.
@MainActor
final class FlowBarHover: ObservableObject {
    static let shared = FlowBarHover()
    @Published var open = false
    @Published var target: FlowBarTarget?
    /// Last control the pointer was on; keeps the label's text and position stable while it fades out.
    @Published var lastTarget: FlowBarTarget = .dictate
    private var closing: DispatchWorkItem?

    func pointer(at p: CGPoint?) {
        guard DictationController.shared.phase == .idle else { closing?.cancel(); set(false, nil); return }
        let zone = open ? FlowBarLayout.openZone : FlowBarLayout.restZone
        if let p, zone.contains(p) {
            closing?.cancel()
            set(true, FlowBarLayout.target(at: p, hovered: target))
        } else if open {
            // Short grace period so a pointer that briefly slips outside does not snap the bar shut.
            set(true, nil)
            closing?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.set(false, nil) }
            closing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    func click(at p: CGPoint) {
        guard open, let t = FlowBarLayout.target(at: p, hovered: target) else { return }
        switch t {
        case .dictate: set(false, nil); DictationController.shared.toggleFromUI()
        case .notetaker: NotetakerController.shared.toggle()
        case .notetakerPage: show(.notetaker)
        case .notes: set(false, nil); NotesWindow.shared.show()
        case .transforms, .transformsPage: show(.transforms)
        }
    }

    private func set(_ isOpen: Bool, _ t: FlowBarTarget?) {
        if (target == nil) != (t == nil) { (t == nil ? NSCursor.arrow : NSCursor.pointingHand).set() }
        if open != isOpen { open = isOpen }
        if target != t { target = t }
        if let t, lastTarget != t { lastTarget = t }
    }

    private func show(_ page: HubPage) {
        set(false, nil)
        Router.shared.page = page
        (NSApp.delegate as? AppDelegate)?.showHub()
    }
}

/// The floating pill at the bottom of the screen (Rattle's "Flow Bar").
/// While idle, hovering it grows the pill into a mic bubble and opens quick actions beside it.
struct FlowBarView: View {
    @ObservedObject var dictation = DictationController.shared
    @ObservedObject var hover = FlowBarHover.shared
    @ObservedObject var notetaker = NotetakerController.shared
    @ObservedObject var store = AppStore.shared
    @LocalState private var dots = 0
    private let tick = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    private static let edge = Color(red: 0.188, green: 0.188, blue: 0.184)       // #30302f
    private static let edgeLit = Color(red: 0.357, green: 0.357, blue: 0.349)    // #5b5b59
    private static let caret = Color(red: 0.529, green: 0.525, blue: 0.514)      // #878683
    private static let well = Color(red: 0.102, green: 0.102, blue: 0.102)       // #1a1a1a
    private static let quick = Animation.timingCurve(0.05, 0.6, 0.4, 0.95, duration: 0.12)
    private static let widen = Animation.spring(response: 0.26, dampingFraction: 0.82)

    private var idle: Bool { dictation.phase == .idle }
    private var open: Bool { idle && hover.open }

    var body: some View {
        ZStack {
            // Nearly invisible fill under the pointer zone, so the transparent panel still gets mouse events there.
            if idle {
                let zone = open ? FlowBarLayout.openZone : FlowBarLayout.restZone
                Color.black.opacity(0.02).frame(width: zone.width, height: zone.height)
                    .position(x: zone.midX, y: FlowBarLayout.panel.height - zone.midY)
            }
            controls
            pill
            tooltip
        }
        .frame(width: FlowBarLayout.panel.width, height: FlowBarLayout.panel.height)
        .animation(Self.quick, value: open)
        .animation(Self.widen, value: hover.target)
    }

    // MARK: Pill (resting, and the dictation states)

    private var pill: some View {
        let resting = idle && !open, lit = open && hover.target == .dictate
        // The icon and dictation content are overlays, so they never decide the pill's size.
        return Capsule().fill(lit ? Self.edge : Color.black.opacity(resting ? 0.5 : 1))
            .overlay(Capsule().strokeBorder(lit ? Self.edgeLit : (resting ? Color.white.opacity(0.5) : Self.edge), lineWidth: 1))
            .overlay { Icon("mic", 15).foregroundStyle(.white).opacity(open ? 1 : 0).scaleEffect(open ? 1 : 0.4) }
            .overlay { content }
            .frame(width: pillWidth, height: pillHeight)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(resting ? 0 : 0.28), radius: 8, y: 2)
            // Bottom edge stays put, so the pill grows upward.
            .position(x: FlowBarLayout.centerX, y: FlowBarLayout.panel.height - FlowBarLayout.bottomInset - pillHeight / 2)
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: dictation.phase)
    }

    private var pillHeight: CGFloat { idle && !open ? FlowBarLayout.pillHeight : FlowBarLayout.height }
    private var pillWidth: CGFloat {
        switch dictation.phase {
        case .idle: return open ? FlowBarLayout.wide : 40
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
            Text(m).font(Theme.sans(11, .medium)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 12)
        }
    }

    // MARK: Control row (always in the tree, so controls scale in and out and slide instead of popping)

    private var controls: some View {
        let h = hover.target
        return ZStack {
            widening(main: .notetaker, more: .notetakerPage) {
                if notetaker.state == .recording { Circle().fill(.red).frame(width: 9, height: 9) }
                else { Icon("record.circle", 14).foregroundStyle(.white) }
            }
            .modifier(Slot(open: open, minX: FlowBarLayout.notetakerMinX, width: FlowBarLayout.notetakerWidth(h)))
            round("note.text", .notes)
                .modifier(Slot(open: open, minX: FlowBarLayout.notesMinX(h), width: FlowBarLayout.control))
            widening(main: .transforms, more: .transformsPage) { Icon("wand.and.stars", 14).foregroundStyle(.white) }
                .modifier(Slot(open: open, minX: FlowBarLayout.transformsMinX(h), width: FlowBarLayout.transformsWidth(h)))
        }
    }

    private func round(_ icon: String, _ target: FlowBarTarget) -> some View {
        let lit = hover.target == target
        return Icon(icon, 14).foregroundStyle(.white)
            .frame(width: FlowBarLayout.control, height: FlowBarLayout.height)
            .background(Circle().fill(lit ? Self.edge : Color.black))
            .overlay(Circle().strokeBorder(lit ? Self.edgeLit : Self.edge, lineWidth: 1.5))
    }

    /// A round control that widens into a pill with a caret tab while the pointer is on it.
    private func widening<Glyph: View>(main: FlowBarTarget, more: FlowBarTarget, @ViewBuilder glyph: () -> Glyph) -> some View {
        let h = hover.target
        let wide = h == main || h == more, lit = h == main
        let width = wide ? FlowBarLayout.wide : FlowBarLayout.control
        return ZStack(alignment: .leading) {
            // The well behind the circle; it only shows once the control widens.
            Capsule().fill(Self.well)
                .overlay(Capsule().strokeBorder(Self.edge.opacity(wide ? 1 : 0), lineWidth: 1.5))
                .overlay(alignment: .trailing) {
                    Icon("chevron.up", 12).foregroundStyle(h == more ? Color.white : Self.caret)
                        .frame(width: 22, height: 22).padding(.trailing, 2).opacity(wide ? 1 : 0)
                }
                .frame(width: width, height: FlowBarLayout.height)
                .clipShape(Capsule())
            glyph()
                .frame(width: FlowBarLayout.control, height: FlowBarLayout.height)
                .background(Circle().fill(lit ? Self.edge : Color.black))
                .overlay(Circle().strokeBorder(lit ? Self.edgeLit : Self.edge, lineWidth: 1.5))
        }
        .frame(width: width, height: FlowBarLayout.height, alignment: .leading)
    }

    // MARK: Label above the hovered control

    private var tooltip: some View {
        let t = hover.lastTarget
        let label: String, key: String?
        switch t {
        case .dictate: label = "Dictate"; key = store.settings.pushTitle
        case .notetaker: label = notetaker.state == .recording ? "Stop meeting" : "Start meeting"; key = nil
        case .notetakerPage: label = "Open Meetings"; key = nil
        case .notes: label = "Open Notes"; key = nil
        case .transforms: label = "Transforms"; key = store.settings.commandModeEnabled ? store.settings.commandTitle : nil
        case .transformsPage: label = "Open Transforms"; key = nil
        }
        let visible = open && hover.target != nil
        return HStack(spacing: 5) {
            Text(label).font(Theme.sans(16))
            if let key { Text(key).font(Theme.sans(16, .bold)) }
        }
        .foregroundStyle(.white).lineLimit(1).fixedSize()
        .padding(.horizontal, 18).frame(height: 36)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Self.edge, lineWidth: 1))
        .opacity(visible ? 1 : 0)
        .position(x: FlowBarLayout.midX(of: t), y: FlowBarLayout.tooltipMidY)
        // The label glides to the next control (180ms) and fades in and out (120ms).
        .animation(.easeInOut(duration: 0.18), value: hover.lastTarget)
        .animation(.easeInOut(duration: 0.12), value: visible)
    }
}

/// Places a side control in its slot, and scales it out from behind the pill when the bar opens.
private struct Slot: ViewModifier {
    let open: Bool
    let minX: CGFloat
    let width: CGFloat
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
            .scaleEffect(open ? 1 : 0.01)
            .opacity(open ? 1 : 0)
            // Closed: tucked behind the pill. Open: in its own slot on the row.
            .position(x: open ? minX + width / 2 : FlowBarLayout.centerX, y: open ? FlowBarLayout.rowMidY : FlowBarLayout.pillMidY)
    }
}

/// Sits on top of the SwiftUI content and turns pointer movement and clicks into FlowBarHover updates.
/// Uses an always-active tracking area so it works while another app is frontmost.
final class FlowBarTrackingView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { FlowBarHover.shared.pointer(at: point(event)) }
    override func mouseMoved(with event: NSEvent) { FlowBarHover.shared.pointer(at: point(event)) }
    override func mouseExited(with event: NSEvent) { FlowBarHover.shared.pointer(at: nil) }
    override func mouseDown(with event: NSEvent) { FlowBarHover.shared.click(at: point(event)) }
}

@MainActor
final class FlowBarWindow {
    private let panel: NSPanel

    init() {
        let size = FlowBarLayout.panel
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // No ignoresMouseEvents: a clear, non-opaque panel already lets clicks through its transparent pixels.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: FlowBarView())
        let tracker = FlowBarTrackingView(frame: container.bounds)
        for v in [host, tracker] as [NSView] {
            v.frame = container.bounds
            v.autoresizingMask = [.width, .height]
            container.addSubview(v)
        }
        panel.contentView = container

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - FlowBarLayout.panel.width / 2, y: f.minY + 2))
    }

    func setVisible(_ v: Bool) { v ? panel.orderFrontRegardless() : panel.orderOut(nil) }
}
