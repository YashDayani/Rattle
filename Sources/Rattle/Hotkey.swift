import Cocoa
import ApplicationServices

/// Global push-to-talk key handling through a CGEvent tap (needs Accessibility permission).
final class HotkeyManager {
    var shortcut: Shortcut = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onHandsFree: (() -> Void)?
    var onCancel: (() -> Void)?
    var isActive: () -> Bool = { false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var down = false

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
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
        tap = nil; source = nil; down = false
    }

    private var keyCode: Int64 {
        switch shortcut {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }
    private var flag: CGEventFlags {
        switch shortcut {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { break }
            let pressed = event.flags.contains(flag)
            if pressed && !down { down = true; DispatchQueue.main.async { self.onPress?() } }
            else if !pressed && down { down = false; DispatchQueue.main.async { self.onRelease?() } }
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if down && code == 49 && onHandsFree != nil { // space while holding → hands-free
                DispatchQueue.main.async { self.onHandsFree?() }
                return nil
            }
            if code == 53 && isActive() { // escape cancels
                DispatchQueue.main.async { self.onCancel?() }
                return nil
            }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
}
