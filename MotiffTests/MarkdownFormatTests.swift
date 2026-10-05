import XCTest

final class MarkdownFormatTests: XCTestCase {
    func testBoldWrapsTheSelectionAndUnwrapsItAgain() {
        let wrapped = MarkdownFormat.bold.apply(to: "soft light", start: 0, end: 4)
        XCTAssertEqual(wrapped.text, "**soft** light")
        XCTAssertEqual(wrapped.start, 2)
        XCTAssertEqual(wrapped.end, 6)

        let unwrapped = MarkdownFormat.bold.apply(to: wrapped.text, start: wrapped.start, end: wrapped.end)
        XCTAssertEqual(unwrapped.text, "soft light")
        XCTAssertEqual(unwrapped.start, 0)
        XCTAssertEqual(unwrapped.end, 4)
    }

    func testItalicWithNothingSelectedPutsTheCursorBetween() {
        let edit = MarkdownFormat.italic.apply(to: "mood", start: 4, end: 4)
        XCTAssertEqual(edit.text, "mood__")
        XCTAssertEqual(edit.start, 5)
        XCTAssertEqual(edit.end, 5)
    }

    func testListPrefixesEveryLineTouchedAndTogglesOff() {
        let text = "light\nshadow\ncolor"
        let listed = MarkdownFormat.bullet.apply(to: text, start: 2, end: 9)
        XCTAssertEqual(listed.text, "- light\n- shadow\ncolor")

        let back = MarkdownFormat.bullet.apply(to: listed.text, start: 3, end: 12)
        XCTAssertEqual(back.text, text)
    }

    func testHeadingGoesAtTheStartOfTheCursorsLine() {
        let edit = MarkdownFormat.heading.apply(to: "intro\nLight study", start: 9, end: 9)
        XCTAssertEqual(edit.text, "intro\n# Light study")
        XCTAssertEqual(edit.start, 11)
    }

    func testLinkSelectsTheAddressToTypeOver() {
        let edit = MarkdownFormat.link.apply(to: "see brief", start: 4, end: 9)
        XCTAssertEqual(edit.text, "see [brief](https://)")
        let characters = Array(edit.text)
        XCTAssertEqual(String(characters[edit.start..<edit.end]), "https://")
    }

    func testOffsetsOutsideTheTextAreClamped() {
        let edit = MarkdownFormat.checklist.apply(to: "todo", start: 40, end: 2)
        XCTAssertEqual(edit.text, "- [ ] todo")
    }
}
