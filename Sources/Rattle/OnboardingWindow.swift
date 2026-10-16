import Cocoa
import SwiftUI

/// Owns the first-run onboarding window. Finishing marks onboarding done; closing early skips the rest for now.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private var finished = false

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        finished = false
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        // Transparent so the view can round the corners like the main window.
        w.isOpaque = false
        w.backgroundColor = .clear
        let root = OnboardingView(finish: { [weak self] in self?.complete() })
            .clipShape(RoundedRectangle(cornerRadius: HubView.windowRadius, style: .continuous))
        let host = NSHostingView(rootView: root)
        host.safeAreaRegions = []
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func complete() {
        finished = true
        AppStore.shared.settings.onboardingDone = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early leaves onboardingDone false, so it comes back on the next launch.
        DictationController.shared.practiceMode = false
        window = nil
        (NSApp.delegate as? AppDelegate)?.showHub()
    }
}
