import CoreGraphics
import SwiftData
import XCTest

final class CanvasViewsTests: XCTestCase {
    @MainActor
    func testOutlineListsRootsDepthFirstThenLooseNodes() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", rootTitle: "Root", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, title: "Idea", in: store.context)
        let card = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, body: "Card", in: store.context)
        let second = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, body: "Second", in: store.context)
        let loose = CanvasGraph.addNode(.note, to: new.canvas, at: .zero, body: "Loose", in: store.context)
        try store.context.save()

        let rows = CanvasOutline.rows(of: new.canvas, collapsed: [])
        XCTAssertEqual(rows.map(\.id), [new.root.id, idea.id, card.id, second.id, loose.id])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 1, 0])
        XCTAssertEqual(rows.map(\.hasChildren), [true, true, false, false, false])

        let folded = CanvasOutline.rows(of: new.canvas, collapsed: [idea.id])
        XCTAssertEqual(folded.map(\.id), [new.root.id, idea.id, second.id, loose.id])
    }

    @MainActor
    func testReorderIndentAndOutdent() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let a = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let b = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let c = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertTrue(CanvasGraph.moveAmongSiblings(c, by: -1))
        XCTAssertEqual(new.root.sortedChildren.map(\.id), [a.id, c.id, b.id])
        XCTAssertFalse(CanvasGraph.moveAmongSiblings(a, by: -1), "already first")

        XCTAssertTrue(CanvasGraph.indent(c, in: store.context))
        XCTAssertTrue(c.parent === a)
        XCTAssertFalse(CanvasGraph.indent(a, in: store.context), "nothing above it to go under")

        XCTAssertTrue(CanvasGraph.outdent(c, in: store.context))
        try store.context.save()
        XCTAssertTrue(c.parent === new.root)
        XCTAssertEqual(new.root.sortedChildren.map(\.id), [a.id, c.id, b.id], "right after its old parent")

        XCTAssertFalse(CanvasGraph.outdent(new.root, in: store.context))
    }

    func testForceLayoutPullsLinkedNodesTogether() {
        // Two chains of three, all starting bunched up.
        let start = (0..<6).map { CGPoint(x: CGFloat($0) * 3, y: CGFloat($0 % 2) * 2) }
        let edges = [(0, 1), (1, 2), (3, 4), (4, 5)]
        let points = ForceLayout.run(positions: start, edges: edges)

        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        func distance(_ a: Int, _ b: Int) -> CGFloat {
            let dx = points[a].x - points[b].x
            let dy = points[a].y - points[b].y
            return (dx * dx + dy * dy).squareRoot()
        }
        let linked = (distance(0, 1) + distance(1, 2) + distance(3, 4) + distance(4, 5)) / 4
        XCTAssertGreaterThan(linked, 20, "spread out from the bunch")
        XCTAssertLessThan(linked, distance(0, 2), "a line is shorter than two hops")
        XCTAssertEqual(ForceLayout.run(positions: start, edges: edges), points, "same input, same layout")
    }
}
