import Foundation

/// A set of physical keys held together, stored as macOS virtual key codes (fn, ⌃⌘V, ⌥M, Esc).
/// Left and right modifiers are different keys, so "Right ⌥" and "⌥" are different chords.
struct KeyChord: Codable, Hashable {
    var keys: [Int]

    init(_ keys: [Int]) { self.keys = Self.ordered(keys) }

    static let modifierCodes: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    var keySet: Set<Int> { Set(keys) }
    var modifiers: Set<Int> { keySet.intersection(Self.modifierCodes) }
    /// The one non-modifier key, if any. A chord holds at most one.
    var mainKey: Int? { keys.first { !Self.modifierCodes.contains($0) } }
    var isModifierOnly: Bool { mainKey == nil && !keys.isEmpty }

    /// Modifiers first in the order macOS prints them, then the key.
    private static func ordered(_ keys: [Int]) -> [Int] {
        let rank: [Int: Int] = [63: 0, 59: 1, 62: 1, 58: 2, 61: 2, 56: 3, 60: 3, 55: 4, 54: 4]
        return Array(Set(keys)).sorted { (rank[$0] ?? 99, $0) < (rank[$1] ?? 99, $1) }
    }

    /// Display chips such as ["fn", "⌃ Ctrl"] or ["⌃ Ctrl", "⌘ Cmd", "v"].
    var parts: [String] { keys.map(Self.name) }
    var title: String { parts.joined(separator: " + ") }

    static func name(_ code: Int) -> String {
        switch code {
        case 63: return "fn"
        case 59: return "⌃ Ctrl"
        case 62: return "Right ⌃"
        case 58: return "⌥ Opt"
        case 61: return "Right ⌥"
        case 56: return "⇧ Shift"
        case 60: return "Right ⇧"
        case 55: return "⌘ Cmd"
        case 54: return "Right ⌘"
        case 49: return "Space"
        case 53: return "esc"
        case 36: return "return"
        case 48: return "tab"
        case 51: return "delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 1002: return "Middle click"
        case let c where isMouse(c): return "Mouse \(c - mouseBase + 1)"
        default: return keyNames[code] ?? "key \(code)"
        }
    }

    private static let keyNames: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
        109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1"
    ]

    /// Mouse buttons other than left and right share the key-code space from 1000: 1002 is the middle button,
    /// 1003 and 1004 the back and forward buttons on the side of most mice.
    static let mouseBase = 1000
    static func isMouse(_ code: Int) -> Bool { code >= mouseBase + 2 }
    static func mouseCode(button: Int) -> Int { mouseBase + button }

    static func isFunctionKey(_ code: Int) -> Bool { [96, 97, 98, 99, 100, 101, 103, 105, 109, 111, 118, 120, 122].contains(code) }

    static let fn = KeyChord([63])
    static let rightOption = KeyChord([61])
    static let rightCommand = KeyChord([54])
    static let rightControl = KeyChord([62])
}

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case pushToTalk, handsFree, pressEnter, commandMode, pasteLast, copyLast, notetaker, cancel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk: return "Push to talk"
        case .handsFree: return "Hands-free mode"
        case .pressEnter: return "Press Enter"
        case .commandMode: return "Command Mode"
        case .pasteLast: return "Paste last transcript"
        case .copyLast: return "Copy last transcript"
        case .notetaker: return "Start or stop Notetaker"
        case .cancel: return "Cancel"
        }
    }

    var detail: String {
        switch self {
        case .pushToTalk: return "Hold to say something short"
        case .handsFree: return "Press while holding push to talk to keep listening, then press again to stop"
        case .pressEnter: return "Trigger Enter with a mouse button (or another key) to send messages faster"
        case .commandMode: return "Select text, hold this and say what to change"
        case .pasteLast: return "Paste the last thing you dictated"
        case .copyLast: return "Copy the last thing you dictated"
        case .notetaker: return "Open Notetaker and start or stop recording a meeting"
        case .cancel: return "Dismiss dictation while it is listening"
        }
    }

    /// Hold actions start on press and end on release; the rest fire once when their key goes down.
    var isHold: Bool { self == .pushToTalk || self == .commandMode }
}

/// Every shortcut Rattle listens for, by action. An action can have several chords.
struct ShortcutBindings: Codable, Equatable {
    static let maxPerAction = 3

    var pushToTalk: [KeyChord] = [.fn]
    var handsFree: [KeyChord] = [KeyChord([63, 49])]
    var pressEnter: [KeyChord] = []
    var commandMode: [KeyChord] = [.rightCommand]
    var pasteLast: [KeyChord] = [KeyChord([59, 55, 9])]
    var copyLast: [KeyChord] = [KeyChord([59, 55, 8])]
    var notetaker: [KeyChord] = [KeyChord([58, 46])]
    var cancel: [KeyChord] = [KeyChord([53])]

    static let `default` = ShortcutBindings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = ShortcutBindings()
        pushToTalk = try c.decodeIfPresent([KeyChord].self, forKey: .pushToTalk) ?? d.pushToTalk
        handsFree = try c.decodeIfPresent([KeyChord].self, forKey: .handsFree) ?? d.handsFree
        pressEnter = try c.decodeIfPresent([KeyChord].self, forKey: .pressEnter) ?? d.pressEnter
        commandMode = try c.decodeIfPresent([KeyChord].self, forKey: .commandMode) ?? d.commandMode
        pasteLast = try c.decodeIfPresent([KeyChord].self, forKey: .pasteLast) ?? d.pasteLast
        copyLast = try c.decodeIfPresent([KeyChord].self, forKey: .copyLast) ?? d.copyLast
        notetaker = try c.decodeIfPresent([KeyChord].self, forKey: .notetaker) ?? d.notetaker
        cancel = try c.decodeIfPresent([KeyChord].self, forKey: .cancel) ?? d.cancel
    }

    enum Keys: String, CodingKey { case pushToTalk, handsFree, pressEnter, commandMode, pasteLast, copyLast, notetaker, cancel }

    subscript(action: ShortcutAction) -> [KeyChord] {
        get {
            switch action {
            case .pushToTalk: return pushToTalk
            case .handsFree: return handsFree
            case .pressEnter: return pressEnter
            case .commandMode: return commandMode
            case .pasteLast: return pasteLast
            case .copyLast: return copyLast
            case .notetaker: return notetaker
            case .cancel: return cancel
            }
        }
        set {
            switch action {
            case .pushToTalk: pushToTalk = newValue
            case .handsFree: handsFree = newValue
            case .pressEnter: pressEnter = newValue
            case .commandMode: commandMode = newValue
            case .pasteLast: pasteLast = newValue
            case .copyLast: copyLast = newValue
            case .notetaker: notetaker = newValue
            case .cancel: cancel = newValue
            }
        }
    }

    /// Why `chord` cannot be used for `action`, or nil when it can. `replacing` is the chord being re-recorded.
    func problem(with chord: KeyChord, for action: ShortcutAction, replacing: KeyChord? = nil) -> String? {
        guard !chord.keys.isEmpty else { return "Press at least one key." }
        if chord.keys.count > 4 { return "Use at most four keys." }
        if chord.keys.filter({ !KeyChord.modifierCodes.contains($0) }).count > 1 { return "Use only one letter, number or symbol key." }

        if action != .cancel && chord.keys == [53] { return "Esc is reserved for Cancel." }
        let hasModifier = !chord.modifiers.isEmpty
        let hasSideButton = chord.keys.contains { KeyChord.isMouse($0) && $0 != 1002 }
        if chord.keys.contains(1002) && !hasModifier { return "Hold a modifier key (fn, ⌃, ⌥, ⇧ or ⌘) with the middle click so it can't break links and tabs." }
        if chord.isModifierOnly && !action.isHold { return "Add a letter, number or Space to the modifier keys." }
        if !chord.isModifierOnly && !hasModifier && !hasSideButton && !chord.keys.allSatisfy(KeyChord.isFunctionKey) && !(action == .cancel && chord.keys == [53]) {
            return "Add a modifier key (fn, ⌃, ⌥, ⇧ or ⌘) so it can't interfere with typing."
        }

        // Standard ⌘ shortcuts (copy, paste, quit, close, switch app) would stop working everywhere.
        if chord.modifiers == [55] || chord.modifiers == [54], let key = chord.mainKey, [8, 9, 7, 6, 0, 12, 13, 1, 48, 49].contains(key) {
            return "⌘\(KeyChord.name(key).uppercased()) is a standard macOS shortcut."
        }

        for other in ShortcutAction.allCases {
            for existing in self[other] where existing == chord && !(other == action && existing == replacing) {
                return other == action ? "That shortcut is already added." : "Already used for \(other.title)."
            }
        }

        // Two hold chords where one is inside the other would fire together (fn and fn + ⌃).
        if action.isHold {
            for other in ShortcutAction.allCases where other.isHold {
                for existing in self[other] where !(other == action && existing == replacing) {
                    if existing.keySet.isSubset(of: chord.keySet) || chord.keySet.isSubset(of: existing.keySet) {
                        return "Conflicts with \(other.title) (\(existing.title))."
                    }
                }
            }
        }
        return nil
    }
}

/// What a key event did to the shortcuts.
enum ShortcutEvent: Equatable {
    case press(ShortcutAction)     // a hold action started
    case release(ShortcutAction)   // a hold action ended
    case trigger(ShortcutAction)   // a one-shot action fired
}

/// Pure shortcut matching, kept apart from the event tap so it can be tested without a keyboard.
///
/// It follows which keys are down. A hold chord made only of modifiers starts when exactly those keys are
/// held and ends when any of them lifts. A chord with a main key fires when that key goes down while exactly
/// its modifiers are held; the key is swallowed so the app underneath never sees it.
struct ChordTracker {
    var bindings = ShortcutBindings.default
    private(set) var down: Set<Int> = []
    private var activeHolds: [ShortcutAction: KeyChord] = [:]
    private var swallowed: Set<Int> = []

    /// Reports whether the key event should be swallowed, plus what it means.
    mutating func key(_ code: Int, isDown: Bool, cancelEnabled: Bool) -> (swallow: Bool, events: [ShortcutEvent]) {
        if isDown {
            guard down.insert(code).inserted else { return (swallowed.contains(code), []) }   // auto-repeat
            return handleDown(code, cancelEnabled: cancelEnabled)
        }
        down.remove(code)
        return (swallowed.remove(code) != nil, releasedHolds())
    }

    /// Clears everything held, for when the event tap was disabled and key-ups may have been missed.
    mutating func reset() -> [ShortcutEvent] {
        down = []; swallowed = []
        return releasedHolds()
    }

    private mutating func releasedHolds() -> [ShortcutEvent] {
        var out: [ShortcutEvent] = []
        for (action, chord) in activeHolds where !chord.keySet.isSubset(of: down) {
            activeHolds[action] = nil
            out.append(.release(action))
        }
        return out
    }

    private mutating func handleDown(_ code: Int, cancelEnabled: Bool) -> (swallow: Bool, events: [ShortcutEvent]) {
        var events: [ShortcutEvent] = []
        let isModifier = KeyChord.modifierCodes.contains(code)
        let heldModifiers = down.intersection(KeyChord.modifierCodes)

        for action in ShortcutAction.allCases {
            if action == .cancel && !cancelEnabled { continue }
            for chord in bindings[action] {
                if action.isHold {
                    guard activeHolds[action] == nil, chord.isModifierOnly || chord.mainKey == code else { continue }
                    if chord.keySet == down && (!chord.isModifierOnly || isModifier) {
                        activeHolds[action] = chord
                        events.append(.press(action))
                        if !chord.isModifierOnly { swallowed.insert(code) }   // don't type the chord's key
                    }
                } else if let main = chord.mainKey, main == code, chord.modifiers == heldModifiers {
                    events.append(.trigger(action))
                    swallowed.insert(code)
                }
            }
        }
        return (swallowed.contains(code), events)
    }
}
