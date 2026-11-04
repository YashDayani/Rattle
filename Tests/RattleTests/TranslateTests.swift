import XCTest
@testable import Rattle

final class TranslateTests: XCTestCase {
    func testTranslateSettingsDefaultOffAndRoundTrip() throws {
        XCTAssertFalse(Settings().translateEnabled)
        var s = Settings(); s.translateEnabled = true; s.translateTo = "ja"
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertTrue(back.translateEnabled); XCTAssertEqual(back.translateTo, "ja")
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"userName":"Ana"}"#.utf8))
        XCTAssertFalse(old.translateEnabled); XCTAssertEqual(old.translateTo, "hi")
    }

    func testPayloadSendsAudioInlineWithTargetLanguage() {
        let p = GeminiAudio.translatePayload(wav: Data([1, 2, 3]), system: "sys", language: "Hindi")
        let part = ((p["contents"] as! [[String: Any]])[0]["parts"] as! [[String: Any]])[0]
        let inline = part["inline_data"] as! [String: String]
        XCTAssertEqual(inline["mime_type"], "audio/wav")
        XCTAssertEqual(inline["data"], Data([1, 2, 3]).base64EncodedString())
    }

    func testExtractTextSkipsThoughts() {
        let j: [String: Any] = ["candidates": [["content": ["parts": [["text": "hmm", "thought": true], ["text": "नमस्ते"]]]]]]
        XCTAssertEqual(GeminiAudio.extractText(j), "नमस्ते")
    }

    func testLanguageNames() { XCTAssertEqual(CloudLanguages.name("hi"), "Hindi") }
}
