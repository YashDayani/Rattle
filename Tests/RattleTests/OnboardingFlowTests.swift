import XCTest
@testable import Rattle

final class OnboardingFlowTests: XCTestCase {
    private let ready = OnboardingChecks(name: "Yash", micGranted: true, axGranted: true, engine: .local,
                                         localModelInstalled: true, whisperInstalled: true, groqKey: "")
    private let nothing = OnboardingChecks(name: "", micGranted: false, axGranted: false, engine: .local,
                                           localModelInstalled: false, whisperInstalled: false, groqKey: "")

    func testNameStepNeedsNonBlankName() {
        var c = ready
        c.name = ""; XCTAssertFalse(OnboardingFlow.canContinue(.name, c))
        c.name = "   "; XCTAssertFalse(OnboardingFlow.canContinue(.name, c))
        c.name = "Yash"; XCTAssertTrue(OnboardingFlow.canContinue(.name, c))
    }

    func testLookAndKeyAlwaysContinue() {
        XCTAssertTrue(OnboardingFlow.canContinue(.look, nothing))
        XCTAssertTrue(OnboardingFlow.canContinue(.key, nothing))
    }

    func testPermissionsNeedBoth() {
        var c = ready
        c.micGranted = false
        XCTAssertFalse(OnboardingFlow.canContinue(.permissions, c))
        XCTAssertTrue(OnboardingFlow.canSkip(.permissions, c))
        c.micGranted = true; c.axGranted = false
        XCTAssertFalse(OnboardingFlow.canContinue(.permissions, c))
        c.axGranted = true
        XCTAssertTrue(OnboardingFlow.canContinue(.permissions, c))
        XCTAssertFalse(OnboardingFlow.canSkip(.permissions, c))
    }

    func testLocalNeedsModelAndWhisper() {
        var c = ready
        c.localModelInstalled = false; XCTAssertFalse(OnboardingFlow.canContinue(.engine, c))
        c.localModelInstalled = true; c.whisperInstalled = false; XCTAssertFalse(OnboardingFlow.canContinue(.engine, c))
        c.whisperInstalled = true; XCTAssertTrue(OnboardingFlow.canContinue(.engine, c))
    }

    func testCloudNeedsKey() {
        var c = ready
        c.engine = .cloud
        for key in ["", "  "] {
            c.groqKey = key
            XCTAssertFalse(OnboardingFlow.canContinue(.engine, c))
            XCTAssertTrue(OnboardingFlow.canSkip(.engine, c))
        }
        c.groqKey = "gsk_x"
        XCTAssertTrue(OnboardingFlow.canContinue(.engine, c))
    }

    func testOnlyPermissionsAndEngineSkip() {
        for step in [OnboardingStep.name, .look, .key, .done] {
            XCTAssertFalse(OnboardingFlow.canSkip(step, nothing))
            XCTAssertFalse(OnboardingFlow.canSkip(step, ready))
        }
    }

    func testNavigation() {
        XCTAssertEqual(OnboardingFlow.next(.name), .look)
        XCTAssertNil(OnboardingFlow.next(.done))
        XCTAssertNil(OnboardingFlow.back(.name))
        XCTAssertEqual(OnboardingFlow.back(.key), .engine)
    }

    func testNoRightCommandChoice() {
        XCTAssertEqual(OnboardingFlow.keyChoices, [.fn, .rightOption, .rightControl])
    }
}
