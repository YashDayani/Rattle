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
        let store = AppStore.shared
        NSApp.setActivationPolicy(store.settings.showInDock ? .regular : .accessory)
        NSApp.applicationIconImage = Self.icon()
        buildMenus()
        buildStatusItem()
        flowBar.setVisible(store.settings.showFlowBar)
        DictationController.shared.boot()
        if let m = WhisperModel.all.first(where: { $0.id == store.settings.model }) { WhisperServer.shared.ensure(model: m) }
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
            w.contentView = host
            w.center()
            w.setFrameAutosaveName("RattleHub2")
            let nc = NotificationCenter.default
            nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { Router.shared.isFullScreen = true }
            }
            nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { Router.shared.isFullScreen = false }
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
            NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.09, alpha: 1).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 40, dy: 40), xRadius: 110, yRadius: 110).fill()
            NSColor.white.setFill()
            let heights: [CGFloat] = [90, 190, 290, 190, 90]
            for (i, h) in heights.enumerated() {
                let x = 130 + CGFloat(i) * 62
                NSBezierPath(roundedRect: NSRect(x: x, y: 256 - h / 2, width: 34, height: h), xRadius: 17, yRadius: 17).fill()
            }
            return true
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
