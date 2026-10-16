import XCTest
@testable import Rattle

final class NamePromptTests: XCTestCase {
    func testBlankNamesAreRejected() {
        XCTAssertNil(NamePrompt.cleaned(""))
        XCTAssertNil(NamePrompt.cleaned("   \n"))
    }

    func testNamesAreTrimmed() {
        XCTAssertEqual(NamePrompt.cleaned("  Work  "), "Work")
    }
}
