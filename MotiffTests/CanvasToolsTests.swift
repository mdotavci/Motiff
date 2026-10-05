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

    // MARK: Stickies, shapes and free arrows

    @MainActor
    func testStickiesAndShapesLandLooseWhereTheyArePut() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let sticky = CanvasGraph.addSticky(to: new.canvas, at: CGPoint(x: 300, y: 0), text: "Soft", in: store.context)
        let star = CanvasGraph.addShape(.star, to: new.canvas, at: CGPoint(x: -300, y: 0), label: "Hero", in: store.context)
        try store.context.save()

        XCTAssertNil(sticky.parent)
        XCTAssertNil(star.parent)
        XCTAssertEqual(sticky.position, CGPoint(x: 300, y: 0))
        XCTAssertEqual(sticky.colorHex, "#F6D77A", "a new sticky is yellow")
        XCTAssertEqual(CanvasLayout.size(of: sticky), CanvasLayout.stickySize)
        XCTAssertEqual(star.shape, .star)
        XCTAssertEqual(star.displayTitle, "Hero")
        XCTAssertEqual(CanvasLayout.size(of: star), CanvasLayout.shapeSize(.star))
        XCTAssertFalse(star.isLine)
    }

    @MainActor
    func testAFreeArrowRunsBetweenItsEndsAndIsLeftOutOfTheOutline() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let arrow = CanvasGraph.addLine(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200), on: new.canvas, in: store.context)
        try store.context.save()

        XCTAssertTrue(arrow.isLine)
        XCTAssertEqual(arrow.shape, .arrow)
        XCTAssertEqual(arrow.position, CGPoint(x: 200, y: 150), "its position is the middle")
        XCTAssertEqual(arrow.line, CGVector(dx: 200, dy: 100))
        let padding = CanvasLayout.linePadding
        XCTAssertEqual(CanvasLayout.size(of: arrow), CGSize(width: 200 + padding * 2, height: 100 + padding * 2))
        XCTAssertFalse(new.canvas.unattachedNodes.contains { $0 === arrow })
        XCTAssertFalse(CanvasOutline.rows(of: new.canvas, collapsed: []).contains { $0.id == arrow.id })

        let snapshot = CanvasSnapshot(canvas: new.canvas)
        let node = try XCTUnwrap(snapshot.node(arrow.id))
        XCTAssertTrue(node.isLine)
        XCTAssertEqual(node.lineStart, CGPoint(x: 100, y: 100))
        XCTAssertEqual(node.lineEnd, CGPoint(x: 300, y: 200))
        XCTAssertEqual(snapshot.nodes.last?.id, arrow.id, "arrows draw on top")
    }

    func testAnArrowIsHitNearItsLineOnly() {
        let arrow = CanvasSnapshot.Node(
            id: UUID(), kind: .shape, rect: CGRect(x: -12, y: -12, width: 224, height: 224), colorHex: nil, title: "Arrow",
            shape: .arrow, line: CGVector(dx: 200, dy: 200)
        )
        XCTAssertTrue(arrow.contains(CGPoint(x: 100, y: 104)), "on the diagonal")
        XCTAssertFalse(arrow.contains(CGPoint(x: 180, y: 20)), "inside its box but far from the line")
    }

    func testAnEllipseIsHitInsideItsCurveOnly() {
        let ellipse = CanvasSnapshot.Node(
            id: UUID(), kind: .shape, rect: CGRect(x: 0, y: 0, width: 200, height: 100), colorHex: nil, title: "Circle",
            shape: .ellipse
        )
        XCTAssertTrue(ellipse.contains(CGPoint(x: 100, y: 50)))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 4, y: 4)), "the corner of its box")
    }

    @MainActor
    func testTheMoodboardExampleHoldsEveryNewKindLoose() throws {
        let store = try TestStore()
        let references = (0..<12).map { _ in store.makeReference(origin: .generated) }
        let board = SeedData.makeMoodboardExample(from: references, in: store.context)
        try store.context.save()

        let nodes = board.nodes
        XCTAssertEqual(nodes.filter { $0.kind == .sticky }.count, 1)
        XCTAssertEqual(Set(nodes.filter { $0.kind == .shape }.map(\.shape)), [.rectangle, .star, .arrow])
        XCTAssertEqual(nodes.filter { $0.kind == .reference }.count, 4)
        XCTAssertEqual(nodes.filter { $0.kind == .prompt }.count, 1)
        XCTAssertEqual(nodes.filter { $0.kind == .text }.count, 1)
        XCTAssertTrue(nodes.allSatisfy { $0.parent == nil }, "a moodboard: nothing belongs to anything")

        let boxes = nodes.filter { !$0.isLine }.map(CanvasGraph.rect(of:))
        for (index, rect) in boxes.enumerated() {
            for other in boxes[(index + 1)...] {
                XCTAssertFalse(rect.intersects(other), "\(rect) covers \(other)")
            }
        }
    }
}
