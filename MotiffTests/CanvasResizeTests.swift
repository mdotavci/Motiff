import CoreGraphics
import SwiftData
import XCTest

/// Step 17: resize anything, size anything's letters, style lines and borders, plain pictures.
final class CanvasResizeTests: XCTestCase {
    func testDraggingACornerKeepsTheOppositeOneInPlace() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let resized = CanvasLayout.resized(rect, corner: .bottomTrailing, to: CGPoint(x: 160, y: 90), keepingAspect: false)
        XCTAssertEqual(resized, CGRect(x: 0, y: 0, width: 160, height: 90))

        let fromTop = CanvasLayout.resized(rect, corner: .topLeading, to: CGPoint(x: -20, y: -30), keepingAspect: false)
        XCTAssertEqual(fromTop, CGRect(x: -20, y: -30, width: 120, height: 80), "the bottom-right corner stays")
    }

    func testPicturesKeepTheirShape() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let resized = CanvasLayout.resized(rect, corner: .bottomTrailing, to: CGPoint(x: 300, y: 60), keepingAspect: true)
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.001)
        XCTAssertEqual(resized.width, 300, accuracy: 0.001, "it follows the side dragged further")
    }

    func testNothingGetsSmallerThanTheMinimumOrFlips() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let resized = CanvasLayout.resized(rect, corner: .bottomTrailing, to: CGPoint(x: -500, y: -500), keepingAspect: false)
        XCTAssertEqual(resized.origin, .zero)
        XCTAssertEqual(resized.size, CGSize(width: CanvasLayout.minimumSide, height: CanvasLayout.minimumSide))
    }

    @MainActor
    func testResizingSetsTheBoxAndKeepsIdeasRound() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let sticky = CanvasGraph.addSticky(to: new.canvas, at: .zero, in: store.context)
        CanvasGraph.resize(sticky, to: CGRect(x: 100, y: 100, width: 300, height: 240))
        XCTAssertEqual(CanvasLayout.size(of: sticky), CGSize(width: 300, height: 240))
        XCTAssertEqual(sticky.position, CGPoint(x: 250, y: 220))

        CanvasGraph.resize(new.root, to: CGRect(x: 0, y: 0, width: 200, height: 150))
        XCTAssertEqual(CanvasLayout.size(of: new.root), CGSize(width: 200, height: 200))

        CanvasGraph.resetSize(sticky)
        XCTAssertEqual(CanvasLayout.size(of: sticky), CanvasLayout.stickySize)
    }

    @MainActor
    func testResizingTextScalesItsLetters() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let text = CanvasGraph.addNode(.text, to: new.canvas, at: .zero, body: "Mood", in: store.context)
        let before = CanvasLayout.size(of: text)

        CanvasGraph.resize(text, to: CGRect(x: 0, y: 0, width: before.width * 2, height: before.height * 2))

        XCTAssertEqual(text.fontSize, TextSize.medium.fontSize * 2)
        XCTAssertNil(text.width, "text keeps growing as it's typed into")
        XCTAssertGreaterThan(CanvasLayout.size(of: text).height, before.height * 1.5)
    }

    @MainActor
    func testLetterSizesStayInRangeAndSkipThingsWithoutWords() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let sticky = CanvasGraph.addSticky(to: new.canvas, at: .zero, in: store.context)
        let arrow = CanvasGraph.addLine(from: .zero, to: CGPoint(x: 100, y: 0), on: new.canvas, in: store.context)

        CanvasGraph.setFontSize(1000, of: [sticky, arrow])
        XCTAssertEqual(sticky.fontSize, 400)
        XCTAssertNil(arrow.fontSize)
        XCTAssertFalse(arrow.hasWords)
    }

    @MainActor
    func testMovingAnArrowsEndKeepsTheOther() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let arrow = CanvasGraph.addLine(from: .zero, to: CGPoint(x: 100, y: 0), on: new.canvas, in: store.context)

        CanvasGraph.setLine(arrow, from: .zero, to: CGPoint(x: 100, y: 100))
        let node = try XCTUnwrap(CanvasSnapshot(canvas: new.canvas).node(arrow.id))
        XCTAssertEqual(node.lineStart, .zero)
        XCTAssertEqual(node.lineEnd, CGPoint(x: 100, y: 100))
    }

    @MainActor
    func testLinkStylesReachTheSnapshot() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let a = CanvasGraph.addNode(.note, to: new.canvas, at: CGPoint(x: -300, y: 0), in: store.context)
        let b = CanvasGraph.addNode(.note, to: new.canvas, at: CGPoint(x: 300, y: 0), in: store.context)
        let link = try XCTUnwrap(CanvasGraph.link(a, to: b, in: store.context))

        CanvasGraph.style(link, width: 4, dashed: false, startArrow: true, endArrow: false)
        let edge = try XCTUnwrap(CanvasSnapshot(canvas: new.canvas).edges.first { $0.type == .relatesTo })
        XCTAssertEqual(edge.width, 4)
        XCTAssertEqual(edge.dashed, false)
        XCTAssertTrue(edge.hasStartArrow)
        XCTAssertFalse(edge.hasArrow)
    }

    @MainActor
    func testPicturesLandOnTheirOwnAndCanGoBackInACard() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let reference = store.makeReference()
        let picture = try XCTUnwrap(CanvasGraph.addReferences([reference], to: new.canvas, in: store.context).first)

        XCTAssertTrue(picture.isBare)
        XCTAssertEqual(CanvasLayout.size(of: picture), CGSize(width: 176, height: 220), "just the picture, no strip or caption")

        CanvasGraph.setBare(false, of: [picture])
        XCTAssertEqual(CanvasLayout.size(of: picture), CGSize(width: 176, height: 262))
    }
}
