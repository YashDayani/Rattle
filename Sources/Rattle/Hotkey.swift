import Cocoa
import ApplicationServices

/// Global shortcut handling through a CGEvent tap (needs Accessibility permission).
/// The matching itself lives in `ChordTracker`; this only turns CGEvents into key transitions.
final class HotkeyManager {
    var bindings: ShortcutBindings {
        get { tracker.bindings }
        set { tracker.bindings = newValue }
    }
    /// Called on the main queue for every shortcut that fires.
    var onEvent: ((ShortcutEvent) -> Void)?
    var isActive: () -> Bool = { false }
    /// While the shortcut editor is recording, keys must reach it instead of triggering dictation.
    var suspended = false {
        didSet { if suspended { release(tracker.reset()) } }
    }

    private var tracker = ChordTracker()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        release(tracker.reset())
    }

    private func release(_ events: [ShortcutEvent]) {
        for e in events { DispatchQueue.main.async { self.onEvent?(e) } }
    }

    /// Which flag a modifier key sets, so a flagsChanged event can say whether it went down or up.
    private static func flag(for code: Int) -> CGEventFlags? {
        switch code {
        case 63: return .maskSecondaryFn
        case 58, 61: return .maskAlternate
        case 54, 55: return .maskCommand
        case 59, 62: return .maskControl
        case 56, 60: return .maskShift
        default: return nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Key-ups may have been lost while the tap was off; forget what was held.
            release(tracker.reset())
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        case .flagsChanged, .keyDown, .keyUp, .otherMouseDown, .otherMouseUp:
            guard !suspended else { return Unmanaged.passUnretained(event) }
            let isMouse = type == .otherMouseDown || type == .otherMouseUp
            let code = isMouse ? KeyChord.mouseCode(button: Int(event.getIntegerValueField(.mouseEventButtonNumber)))
                               : Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isDown: Bool
            if type == .flagsChanged {
                guard let flag = Self.flag(for: code) else { return Unmanaged.passUnretained(event) }
                isDown = event.flags.contains(flag)
            } else {
                isDown = type == .keyDown || type == .otherMouseDown
            }
            let result = tracker.key(code, isDown: isDown, cancelEnabled: isActive())
            release(result.events)
            return result.swallow ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
