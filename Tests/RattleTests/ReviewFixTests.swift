import XCTest
import AVFoundation
@testable import Rattle

final class ReviewFixTests: XCTestCase {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rattle-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func testEmptySupportFolderIsANewUser() throws {
        XCTAssertFalse(AppStore.hasPriorUse(in: try tempDir()))
    }

    func testHistoryWithoutSettingsIsAnExistingUser() throws {
        let d = try tempDir()
        try Data("[]".utf8).write(to: d.appendingPathComponent("history.json"))
        XCTAssertTrue(AppStore.hasPriorUse(in: d))
    }

    func testDownloadedModelIsAnExistingUser() throws {
        let d = try tempDir()
        try FileManager.default.createDirectory(at: d.appendingPathComponent("models"), withIntermediateDirectories: true)
        try Data().write(to: d.appendingPathComponent("models/ggml-base.en.bin"))
        XCTAssertTrue(AppStore.hasPriorUse(in: d))
    }

    func testDeniedMicOpensSystemSettings() {
        XCTAssertTrue(OnboardingFlow.micAllowOpensSettings(.denied))
        XCTAssertTrue(OnboardingFlow.micAllowOpensSettings(.restricted))
        XCTAssertFalse(OnboardingFlow.micAllowOpensSettings(.notDetermined))
    }

    func testPracticeOnlyWhenRattleWasFrontmost() {
        XCTAssertTrue(DictationController.isPractice(practiceMode: true, frontPID: 42, ownPID: 42))
        XCTAssertFalse(DictationController.isPractice(practiceMode: true, frontPID: 7, ownPID: 42))
        XCTAssertFalse(DictationController.isPractice(practiceMode: true, frontPID: nil, ownPID: 42))
        XCTAssertFalse(DictationController.isPractice(practiceMode: false, frontPID: 42, ownPID: 42))
    }
}
