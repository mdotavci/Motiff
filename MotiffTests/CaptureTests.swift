import XCTest

final class CaptureTests: XCTestCase {
    func testPurposeGuesses() {
        XCTAssertEqual(PromptPurposeGuess.guess("matte ceramic mug on linen --ar 4:5 --v 7"), .image)
        XCTAssertEqual(PromptPurposeGuess.guess("Cinematic portrait of a chef, 85mm, soft lighting"), .image)
        XCTAssertEqual(PromptPurposeGuess.guess("Refactor this SwiftUI view to use @Observable and add a unit test"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("Fix this:\n```\nlet x = 1\n```"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("if (x) {\n  run();\n}"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("Rewrite this paragraph so it's half as long and warmer."), .text)
        XCTAssertEqual(
            PromptPurposeGuess.guess("Write a three-line shot brief for a product photo: subject, light, mood."),
            .text
        )
    }
}
