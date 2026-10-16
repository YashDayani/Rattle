import XCTest
@testable import Rattle

@MainActor
final class IllustrationTests: XCTestCase {
    func testEmptyStateArtLoads() {
        for art in [Illustration.dictationEmpty, Illustration.meetingsEmpty, Illustration.notesEmpty] {
            XCTAssertNotNil(Illustration.image(art), "no art for \(art)")
        }
    }

    func testEmptyStatesDontReuseOnboardingArt() {
        let onboarding = Set(OnboardingStep.allCases.map(OnboardingArt.file(for:)))
        for art in [Illustration.dictationEmpty, Illustration.meetingsEmpty, Illustration.notesEmpty] {
            XCTAssertFalse(onboarding.contains(art), "\(art) is also used in onboarding")
        }
    }
}
