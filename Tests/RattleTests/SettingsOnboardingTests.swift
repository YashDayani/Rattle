import XCTest
@testable import Rattle

final class SettingsOnboardingTests: XCTestCase {
    func testFreshSettingsNeedOnboarding() { XCTAssertFalse(Settings().onboardingDone) }

    func testExistingSettingsFileSkipsOnboarding() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"userName":"Ana"}"#.utf8))
        XCTAssertTrue(s.onboardingDone)
    }

    func testOnboardingFlagRoundTrips() throws {
        var s = Settings(); s.onboardingDone = false
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertFalse(back.onboardingDone)
    }
}
