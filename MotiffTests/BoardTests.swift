import CoreGraphics
import SwiftData
import XCTest

/// Boards are Canvases now: References go on them as loose cards, and the old grid Boards
/// turn into boards once.
final class BoardTests: XCTestCase {
    @MainActor
    func testAddingAReferenceTwiceKeepsOneCard() throws {
        let store = try TestStore()
        let board = CanvasGraph.makeCanvas(title: "Mood", in: store.context).canvas
        let first = store.makeReference()
        let second = store.makeReference()

        let made = CanvasGraph.addReferences([first, second, first], to: board, in: store.context)
        CanvasGraph.addReferences([first], to: board, in: store.context)
        try store.context.save()

        XCTAssertEqual(made.count, 2)
        XCTAssertEqual(CanvasGraph.cards(of: first, on: board).count, 1)
        XCTAssertEqual(CanvasGraph.cards(of: second, on: board).count, 1)
        XCTAssertTrue(made.allSatisfy { $0.parent == nil }, "they land loose, not under the root")
    }

    @MainActor
    func testAddedCardsDontCoverWhatsThere() throws {
        let store = try TestStore()
        let board = CanvasGraph.makeCanvas(title: "Mood", in: store.context).canvas
        let references = (0..<6).map { _ in store.makeReference() }

        CanvasGraph.addReferences(references, to: board, in: store.context)
        CanvasGraph.addReferences([store.makeReference()], to: board, in: store.context)

        let rects = board.nodes.map(CanvasGraph.rect(of:))
        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                XCTAssertFalse(rect.intersects(other), "\(rect) covers \(other)")
            }
        }
    }

    @MainActor
    func testTakingACardOffKeepsTheReference() throws {
        let store = try TestStore()
        let board = CanvasGraph.makeCanvas(title: "Mood", in: store.context).canvas
        let reference = store.makeReference()
        CanvasGraph.addReferences([reference], to: board, in: store.context)

        CanvasGraph.delete(CanvasGraph.cards(of: reference, on: board), branch: false, in: store.context)
        try store.context.save()

        XCTAssertTrue(CanvasGraph.cards(of: reference, on: board).isEmpty)
        XCTAssertEqual(try store.count(Reference.self), 1)
    }

    @MainActor
    func testAnOldBoardBecomesABoardWithEachReferenceOnce() throws {
        let store = try TestStore()
        let old = Board(name: "Product photography")
        store.context.insert(old)
        let older = store.makeReference()
        older.createdAt = .now.addingTimeInterval(-60)
        let newer = store.makeReference()
        old.references = [older, newer]

        let board = CanvasGraph.makeCanvas(from: old, in: store.context)
        try store.context.save()

        XCTAssertEqual(board.title, "Product photography")
        XCTAssertEqual(board.roots.first?.title, "Product photography")
        let cards = board.nodes.filter { $0.reference != nil }
        XCTAssertEqual(Set(cards.compactMap { $0.reference?.id }), [older.id, newer.id])
        XCTAssertEqual(cards.count, 2)
        // Newest first, left to right.
        let newerCard = try XCTUnwrap(cards.first { $0.reference === newer })
        let olderCard = try XCTUnwrap(cards.first { $0.reference === older })
        XCTAssertLessThan(newerCard.x, olderCard.x)
        // Under the root, not on top of it.
        let root = try XCTUnwrap(board.roots.first)
        XCTAssertFalse(cards.contains { CanvasGraph.rect(of: $0).intersects(CanvasGraph.rect(of: root)) })
    }

    @MainActor
    func testAnUnnamedOldBoardKeepsADisplayName() throws {
        let store = try TestStore()
        let old = Board(name: "  ")
        store.context.insert(old)
        XCTAssertEqual(old.displayName, "Untitled board")
        XCTAssertEqual(CanvasGraph.makeCanvas(from: old, in: store.context).roots.first?.title, "Untitled board")
    }

    func testGridRowsAreAsTallAsTheirTallestItem() {
        let sizes = [CGSize(width: 100, height: 50), CGSize(width: 100, height: 150), CGSize(width: 100, height: 80)]
        let centers = CanvasLayout.gridCenters(for: sizes, columns: 2, topLeft: .zero, gap: 10)
        XCTAssertEqual(centers[0], CGPoint(x: 50, y: 25))
        XCTAssertEqual(centers[1], CGPoint(x: 160, y: 75))
        XCTAssertEqual(centers[2], CGPoint(x: 50, y: 160 + 40), "the second row starts under the tallest one")
    }

    func testAnOpenSpotStaysPutWhenFree() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(CanvasLayout.openSpot(for: size, near: CGPoint(x: 500, y: 500), avoiding: [CGRect(x: 0, y: 0, width: 100, height: 100)]), CGPoint(x: 500, y: 500))
        let taken = CGRect(x: 450, y: 450, width: 100, height: 100)
        let moved = CanvasLayout.openSpot(for: size, near: CGPoint(x: 500, y: 500), avoiding: [taken])
        XCTAssertFalse(CGRect(x: moved.x - 50, y: moved.y - 50, width: 100, height: 100).intersects(taken))
    }
}
