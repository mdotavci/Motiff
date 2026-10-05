import CoreGraphics
import SwiftData
import XCTest

final class CanvasEditingTests: XCTestCase {
    func testRadialSlotsNeverOverlap() {
        var occupied = [CGRect(x: -64, y: -64, width: 128, height: 128)]
        let size = CGSize(width: 224, height: 112)
        for _ in 0..<24 {
            let point = CanvasLayout.radialSlot(around: .zero, radius: 64, size: size, avoiding: occupied)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
            XCTAssertFalse(occupied.contains { $0.intersects(rect) }, "slot \(occupied.count) overlaps")
            occupied.append(rect)
        }
    }

    func testRadialSlotStartsOnThePreferredSide() {
        let point = CanvasLayout.radialSlot(
            around: .zero, radius: 44, size: CGSize(width: 64, height: 64), avoiding: [], startAngle: .pi
        )
        XCTAssertLessThan(point.x, 0)
        XCTAssertEqual(point.y, 0, accuracy: 0.001)
    }

    @MainActor
    func testChildrenArePlacedAroundTheirIdeaWithoutCoveringAnything() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        var placed: [CanvasNode] = []
        for index in 0..<10 {
            let kind: NodeKind = index.isMultiple(of: 3) ? .idea : .note
            let node = try XCTUnwrap(CanvasGraph.addChild(kind, under: new.root, in: store.context))
            placed.append(node)
        }
        try store.context.save()

        let rects = new.canvas.nodes.map { CanvasGraph.rect(of: $0) }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "\(a) overlaps \(b)")
            }
        }
        XCTAssertTrue(placed.allSatisfy { $0.parent === new.root })
    }

    @MainActor
    func testMovedNodesStayWhereTheyWereDropped() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let note = try XCTUnwrap(CanvasGraph.addChild(.note, under: new.root, in: store.context))
        CanvasGraph.move([note], by: CGSize(width: 500, height: -300))
        let dropped = note.position
        CanvasGraph.addChild(.note, under: new.root, in: store.context)
        try store.context.save()

        XCTAssertEqual(note.position, dropped, "adding a sibling doesn't move it")
    }

    @MainActor
    func testRenamingTheRootNamesAnUntitledCanvas() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        CanvasGraph.rename(new.root, to: "  Spring campaign ")
        XCTAssertEqual(new.root.title, "Spring campaign")
        XCTAssertEqual(new.canvas.title, "Spring campaign")

        CanvasGraph.rename(new.root, to: "Autumn")
        XCTAssertEqual(new.canvas.title, "Spring campaign", "a named Canvas keeps its name")
    }

    @MainActor
    func testCategoryFollowsAnIdeaToItsCards() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let amber = new.categories[0]
        let blue = new.categories[1]
        let teal = new.categories[3]
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, category: amber, in: store.context)
        let inherited = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        let own = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, category: teal, in: store.context)

        CanvasGraph.setCategory([idea], to: blue)

        XCTAssertTrue(idea.category === blue)
        XCTAssertTrue(inherited.category === blue)
        XCTAssertTrue(own.category === teal)
    }

    @MainActor
    func testDeleteKeepsTheRootAndHandlesNestedSelections() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let card = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertEqual(CanvasGraph.delete([new.root], branch: true, in: store.context), 0)
        XCTAssertEqual(CanvasGraph.delete([new.root, idea, card], branch: true, in: store.context), 2)
        try store.context.save()

        XCTAssertEqual(try store.count(CanvasNode.self), 1)
        XCTAssertEqual(new.canvas.roots.count, 1)
    }

    @MainActor
    func testSiblingsAreTheNodesAtTheSameLevelInOrder() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let first = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let second = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let loose = CanvasGraph.addNode(.note, to: new.canvas, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertEqual(CanvasGraph.siblings(of: second).map(\.id), [first.id, second.id])
        XCTAssertEqual(CanvasGraph.siblings(of: new.root).map(\.id), [new.root.id])
        XCTAssertEqual(CanvasGraph.siblings(of: loose).map(\.id), [loose.id])
    }
}
