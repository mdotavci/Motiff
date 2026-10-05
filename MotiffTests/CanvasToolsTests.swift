import CoreGraphics
import SwiftData
import XCTest

final class CanvasToolsTests: XCTestCase {
    func testTextBoxGrowsWithItsTextAndWraps() {
        let empty = CanvasLayout.textBox(for: "", size: .medium)
        let word = CanvasLayout.textBox(for: "Light", size: .medium)
        let sentence = CanvasLayout.textBox(for: "Hard light reads confident, soft light reads calm", size: .medium)
        let paragraph = CanvasLayout.textBox(for: String(repeating: "negative space ", count: 20), size: .medium)

        XCTAssertGreaterThan(empty.width, 0)
        XCTAssertGreaterThan(empty.height, 0)
        XCTAssertGreaterThanOrEqual(sentence.width, word.width)
        XCTAssertEqual(paragraph.width, CanvasLayout.textMaxWidth, "long text wraps at the maximum width")
        XCTAssertGreaterThan(paragraph.height, sentence.height)
    }

    func testBiggerTextSizesTakeMoreRoom() {
        let sizes = TextSize.allCases.map { CanvasLayout.textBox(for: "Product photography", size: $0) }
        for (smaller, bigger) in zip(sizes, sizes.dropFirst()) {
            XCTAssertGreaterThan(bigger.height, smaller.height)
        }
    }

    func testEveryLineCountsWhenTextHasLineBreaks() {
        let one = CanvasLayout.textBox(for: "Light", size: .small)
        let three = CanvasLayout.textBox(for: "Light\nShadow\nColor", size: .small)
        XCTAssertGreaterThan(three.height, one.height * 2)
    }

    @MainActor
    func testTextNodesAreSizedByTheirTextAndKeepTheirSize() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let text = CanvasGraph.addNode(.text, to: new.canvas, at: CGPoint(x: 400, y: 300), body: "Mood", in: store.context)
        text.textSize = .huge
        try store.context.save()

        XCTAssertEqual(text.textSize, .huge)
        XCTAssertEqual(CanvasLayout.size(of: text), CanvasLayout.textBox(for: "Mood", size: .huge))
        XCTAssertEqual(text.displayTitle, "Mood")
        XCTAssertNil(text.parent, "placed on empty space it stays loose")
        XCTAssertEqual(text.position, CGPoint(x: 400, y: 300))
    }

    @MainActor
    func testATextNodeLeftEmptyIsNamedSo() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let text = try XCTUnwrap(CanvasGraph.addChild(.text, under: new.root, body: "", in: store.context))
        XCTAssertEqual(text.displayTitle, "Empty text")
        XCTAssertEqual(text.textSize, .medium)
    }
}
