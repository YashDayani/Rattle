import XCTest
@testable import Rattle

@MainActor
final class OnboardingArtTests: XCTestCase {
    func testEveryStepHasArt() {
        for step in OnboardingStep.allCases {
            let image = OnboardingArt.image(for: step)
            XCTAssertNotNil(image, "no art for \(step)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        }
    }

    func testArtUsesRattleInk() throws {
        for step in OnboardingStep.allCases {
            let url = try XCTUnwrap(OnboardingArt.url(for: step))
            let svg = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(svg.contains("#1a1a1a"), "\(step) missing Rattle ink")
            XCTAssertFalse(svg.uppercased().contains("#FF5678"), "\(step) still has the original accent")
            XCTAssertFalse(svg.contains("#000000"), "\(step) still has pure black")
        }
    }
}
