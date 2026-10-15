import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var hub: NSWindow?
    var flowBar = FlowBarWindow()
    var statusItem: NSStatusItem?

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        // SIGTERM/SIGINT skip applicationWillTerminate; make sure the speech server goes down with us.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { WhisperServer.shared.stop(); exit(0) }
            src.resume()
            signalSources.append(src)
        }
        Theme.registerFonts()
        let store = AppStore.shared
        Theme.apply(store.settings.appearance)
        NSApp.setActivationPolicy(store.settings.showInDock ? .regular : .accessory)
        // A bundle built with an Icon Composer icon gets the system's glass styling; only draw our own when it has none.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") == nil { NSApp.applicationIconImage = Self.icon() }
        buildMenus()
        buildStatusItem()
        flowBar.setVisible(store.settings.showFlowBar)
        DictationController.shared.boot()
        if store.settings.speechEngine == .local, let m = WhisperModel.all.first(where: { $0.id == store.settings.model }) { WhisperServer.shared.ensure(model: m) }
        showHub()
        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showHub(); return true }
    func applicationWillTerminate(_ notification: Notification) { WhisperServer.shared.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func showHub() {
        if hub == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            // An empty unified toolbar gives a 52pt title bar, so the traffic lights centre on the chrome row.
            w.toolbar = NSToolbar(identifier: "hub")
            w.toolbar?.showsBaselineSeparator = false
            w.toolbarStyle = .unified
            w.minSize = NSSize(width: 1040, height: 700)
            if let vis = NSScreen.main?.visibleFrame {
                var f = w.frame
                f.size.width = min(f.width, vis.width - 40); f.size.height = min(f.height, vis.height - 20)
                w.setFrame(f, display: false)
            }
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace]   // always appear where the user is looking
            // Keep the window at the size the user chose; pages scroll instead of pushing its minimum size up.
            let host = NSHostingView(rootView: HubView())
            host.sizingOptions = []
            // The layout draws its own title row, so it always gets the full window, title bar included.
            // (Relying on ignoresSafeArea left a strip uncovered whenever a page was taller than the area below the title bar.)
            host.safeAreaRegions = []
            w.contentView = host
            w.backgroundColor = NSColor(Theme.window)
            w.contentMinSize = NSSize(width: 960, height: 560)
            w.center()
            w.setFrameAutosaveName("RattleHub2")
            let nc = NotificationCenter.default
            // In full screen the toolbar turns into an opaque band that covers our own title row, so hide it there.
            nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { [weak w] _ in
                MainActor.assumeIsolated { w?.toolbar?.isVisible = false; Router.shared.isFullScreen = true }
            }
            nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { [weak w] _ in
                MainActor.assumeIsolated { w?.toolbar?.isVisible = true; Router.shared.isFullScreen = false }
            }
            hub = w
        }
        hub?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Lucide.image("waveform", size: 18)
        let m = NSMenu()
        m.addItem(withTitle: "Open Rattle", action: #selector(showHub), keyEquivalent: "").target = self
        m.addItem(NSMenuItem.separator())
        let copy = NSMenuItem(title: "Copy last dictation", action: #selector(copyLast), keyEquivalent: "")
        copy.target = self; m.addItem(copy)
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "Quit Rattle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = m
        statusItem = item
    }

    @objc private func copyLast() {
        guard let t = AppStore.shared.history.first?.text else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
    }

    private func buildMenus() {
        let main = NSMenu()
        let app = NSMenuItem(); main.addItem(app)
        let am = NSMenu(); app.submenu = am
        am.addItem(withTitle: "About Rattle", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        am.addItem(NSMenuItem.separator())
        am.addItem(withTitle: "Hide Rattle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        am.addItem(withTitle: "Quit Rattle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); main.addItem(edit)
        let em = NSMenu(title: "Edit"); edit.submenu = em
        em.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        em.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        em.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        em.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        em.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    static func icon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { r in
        let s = r.width / 512
        let body = NSRect(x: 40 * s, y: 40 * s, width: r.width - 80 * s, height: r.width - 80 * s)
        let radius = 110 * s
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    // Soft dark drop shadow, like system icons.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow(); drop.shadowColor = NSColor.black.withAlphaComponent(0.45); drop.shadowBlurRadius = 14 * s; drop.shadowOffset = NSSize(width: 0, height: -6 * s)
    drop.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
        // Dark body with a faint lift at the top.
        NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.17, alpha: 1), ending: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.07, alpha: 1))!.draw(in: path, angle: -90)
        // Waveform, centred on the icon (total width 4 * 62 + 34 = 282).
        NSGraphicsContext.saveGraphicsState()
        let bars = NSShadow(); bars.shadowColor = NSColor.white.withAlphaComponent(0.45); bars.shadowBlurRadius = 14 * s; bars.shadowOffset = .zero
        bars.set()
        NSColor.white.setFill()
        let heights: [CGFloat] = [90, 190, 290, 190, 90]
        for (i, h) in heights.enumerated() {
            let x = (115 + CGFloat(i) * 62) * s
            NSBezierPath(roundedRect: NSRect(x: x, y: (256 - h / 2) * s, width: 34 * s, height: h * s), xRadius: 17 * s, yRadius: 17 * s).fill()
        }
            return true
        }
    }
}

extension CGPath {
    var nsPath: NSBezierPath {
        let p = NSBezierPath()
        applyWithBlock { e in
            let pt = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: p.move(to: pt[0])
            case .addLineToPoint: p.line(to: pt[0])
            case .addCurveToPoint: p.curve(to: pt[2], controlPoint1: pt[0], controlPoint2: pt[1])
            case .addQuadCurveToPoint: p.curve(to: pt[1], controlPoint1: pt[0], controlPoint2: pt[0])
            case .closeSubpath: p.close()
            @unknown default: break
            }
        }
        return p
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let p = CGMutablePath(); var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo: p.move(to: pts[0])
            case .lineTo: p.addLine(to: pts[0])
            case .curveTo: p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath: p.closeSubpath()
            default: break
            }
        }
        return p
    }
}


// `Rattle --mcp` is launched by MCP clients (Claude Desktop, Cursor…) as a headless stdio server.
if CommandLine.arguments.contains("--mcp") { MCPServer.run() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
