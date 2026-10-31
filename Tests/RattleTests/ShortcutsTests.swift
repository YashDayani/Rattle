import XCTest
@testable import Rattle

final class ShortcutsTests: XCTestCase {
    private let fn = 63, ctrl = 59, cmd = 55, opt = 58, space = 49, esc = 53, v = 9, m = 46

    private func press(_ t: inout ChordTracker, _ code: Int, cancel: Bool = false) -> [ShortcutEvent] { t.key(code, isDown: true, cancelEnabled: cancel).events }
    private func lift(_ t: inout ChordTracker, _ code: Int) -> [ShortcutEvent] { t.key(code, isDown: false, cancelEnabled: false).events }

    func testPushToTalkHoldsAndReleases() {
        var t = ChordTracker()
        XCTAssertEqual(press(&t, fn), [.press(.pushToTalk)])
        XCTAssertEqual(lift(&t, fn), [.release(.pushToTalk)])
    }

    func testHandsFreeIsFnThenSpaceAndSwallowsSpace() {
        var t = ChordTracker()
        _ = press(&t, fn)
        let r = t.key(space, isDown: true, cancelEnabled: false)
        XCTAssertEqual(r.events, [.trigger(.handsFree)])
        XCTAssertTrue(r.swallow)
        XCTAssertTrue(t.key(space, isDown: false, cancelEnabled: false).swallow)   // the key-up is swallowed too
    }

    func testChordNeedsExactModifiers() {
        var t = ChordTracker()
        _ = press(&t, ctrl); _ = press(&t, cmd)
        XCTAssertEqual(press(&t, v), [.trigger(.pasteLast)])
        var extra = ChordTracker()
        _ = press(&extra, ctrl); _ = press(&extra, cmd); _ = press(&extra, 56)
        XCTAssertEqual(press(&extra, v), [])
    }

    func testAutoRepeatDoesNotFireTwice() {
        var t = ChordTracker()
        _ = press(&t, opt)
        XCTAssertEqual(press(&t, m), [.trigger(.notetaker)])
        XCTAssertEqual(press(&t, m), [])
    }

    func testCancelOnlyWhileListening() {
        var t = ChordTracker()
        XCTAssertEqual(press(&t, esc, cancel: false), [])
        _ = lift(&t, esc)
        XCTAssertEqual(press(&t, esc, cancel: true), [.trigger(.cancel)])
    }

    func testPushToTalkChordWithMainKeyHoldsUntilKeyLifts() {
        var t = ChordTracker()
        t.bindings.pushToTalk = [KeyChord([opt, space])]
        _ = press(&t, opt)
        XCTAssertEqual(press(&t, space), [.press(.pushToTalk)])
        XCTAssertEqual(lift(&t, space), [.release(.pushToTalk)])
    }

    func testResetReleasesHeldShortcuts() {
        var t = ChordTracker()
        _ = press(&t, fn)
        XCTAssertEqual(t.reset(), [.release(.pushToTalk)])
    }

    func testUnboundActionDoesNothing() {
        var t = ChordTracker()
        t.bindings.pasteLast = []
        _ = press(&t, ctrl); _ = press(&t, cmd)
        XCTAssertEqual(press(&t, v), [])
    }

    // MARK: Mouse buttons

    private let mouse4 = KeyChord.mouseCode(button: 3), mouse5 = KeyChord.mouseCode(button: 4), middle = KeyChord.mouseCode(button: 2)

    func testSideButtonFiresPressEnterAndSwallowsTheClick() {
        var t = ChordTracker()
        t.bindings.pressEnter = [KeyChord([mouse4])]
        let down = t.key(mouse4, isDown: true, cancelEnabled: false)
        XCTAssertEqual(down.events, [.trigger(.pressEnter)])
        XCTAssertTrue(down.swallow)
        XCTAssertTrue(t.key(mouse4, isDown: false, cancelEnabled: false).swallow)   // so the browser doesn't also go back
    }

    func testSideButtonCanBePushToTalk() {
        var t = ChordTracker()
        t.bindings.pushToTalk = [KeyChord([mouse5])]
        XCTAssertEqual(press(&t, mouse5), [.press(.pushToTalk)])
        XCTAssertEqual(lift(&t, mouse5), [.release(.pushToTalk)])
    }

    func testMouseButtonWithModifier() {
        var t = ChordTracker()
        t.bindings.copyLast = [KeyChord([opt, mouse4])]
        _ = press(&t, opt)
        XCTAssertEqual(press(&t, mouse4), [.trigger(.copyLast)])
    }

    func testSideButtonsNeedNoModifierButMiddleClickDoes() {
        let b = ShortcutBindings.default
        XCTAssertNil(b.problem(with: KeyChord([mouse4]), for: .pressEnter))
        XCTAssertNil(b.problem(with: KeyChord([mouse5]), for: .handsFree))
        XCTAssertNotNil(b.problem(with: KeyChord([middle]), for: .pressEnter))
        XCTAssertNil(b.problem(with: KeyChord([ctrl, middle]), for: .pressEnter))
    }

    func testMouseButtonNames() {
        XCTAssertEqual(KeyChord([mouse4]).title, "Mouse 4")
        XCTAssertEqual(KeyChord([mouse5]).title, "Mouse 5")
        XCTAssertEqual(KeyChord([KeyChord.mouseCode(button: 5)]).title, "Mouse 6")
        XCTAssertEqual(KeyChord([middle]).title, "Middle click")
    }

    func testPressEnterIsUnboundByDefault() {
        XCTAssertEqual(ShortcutBindings.default.pressEnter, [])
    }

    // MARK: Validation

    func testRejectsBareLetterButAllowsFunctionKey() {
        let b = ShortcutBindings.default
        XCTAssertNotNil(b.problem(with: KeyChord([v]), for: .pasteLast))
        XCTAssertNil(b.problem(with: KeyChord([122]), for: .pasteLast))
    }

    func testModifierOnlyOnlyForHoldActions() {
        let b = ShortcutBindings.default
        XCTAssertNil(b.problem(with: KeyChord([ctrl, opt]), for: .commandMode))
        XCTAssertNotNil(b.problem(with: KeyChord([ctrl, opt]), for: .copyLast))
    }

    func testNamesTheActionThatOwnsAChord() {
        let b = ShortcutBindings.default
        XCTAssertEqual(b.problem(with: KeyChord([ctrl, cmd, v]), for: .copyLast), "Already used for Paste last transcript.")
    }

    func testReRecordingAChordAsItselfIsAllowed() {
        let b = ShortcutBindings.default
        XCTAssertNil(b.problem(with: .fn, for: .pushToTalk, replacing: .fn))
    }

    func testHoldChordsMayNotNestInsideEachOther() {
        let b = ShortcutBindings.default
        XCTAssertNotNil(b.problem(with: KeyChord([fn, ctrl]), for: .commandMode))   // fn is push to talk
    }

    func testEscIsReservedForCancel() {
        let b = ShortcutBindings.default
        XCTAssertNotNil(b.problem(with: KeyChord([esc]), for: .pushToTalk))
    }

    func testRefusesStandardCommandShortcuts() {
        XCTAssertNotNil(ShortcutBindings.default.problem(with: KeyChord([cmd, v]), for: .notetaker))
    }

    func testTitleOrdersModifiersFirst() {
        XCTAssertEqual(KeyChord([v, cmd, ctrl]).title, "⌃ Ctrl + ⌘ Cmd + v")
    }

    // MARK: Settings

    func testOldSettingsKeepTheirKeys() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"shortcut":"rightOption","commandShortcut":"rightControl"}"#.utf8))
        XCTAssertEqual(s.bindings.pushToTalk, [.rightOption])
        XCTAssertEqual(s.bindings.handsFree, [KeyChord([61, 49])])
        XCTAssertEqual(s.bindings.commandMode, [.rightControl])
        XCTAssertEqual(s.shortcut, .rightOption)
    }

    func testBindingsRoundTrip() throws {
        var s = Settings()
        s.bindings.pasteLast = [KeyChord([opt, 35])]
        s.bindings.copyLast = []
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.bindings, s.bindings)
        XCTAssertEqual(back.bindings.copyLast, [])
    }

    func testMissingActionFallsBackToItsDefault() throws {
        let b = try JSONDecoder().decode(ShortcutBindings.self, from: Data(#"{"pushToTalk":[{"keys":[61]}]}"#.utf8))
        XCTAssertEqual(b.pushToTalk, [.rightOption])
        XCTAssertEqual(b.cancel, ShortcutBindings.default.cancel)
    }
}
