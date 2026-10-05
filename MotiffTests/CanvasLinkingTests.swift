import CoreGraphics
import SwiftData
import XCTest

final class CanvasLinkingTests: XCTestCase {
    @MainActor
    func testBelongingBecomesALinkAndBackKeepingTheLabel() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let note = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        CanvasGraph.setLabel("why", child: note)
        try store.context.save()

        let link = try XCTUnwrap(CanvasGraph.convertToLink(child: note, in: store.context))
        try store.context.save()
        XCTAssertNil(note.parent)
        XCTAssertNil(note.parentLabel)
        XCTAssertTrue(link.from === idea && link.to === note)
        XCTAssertEqual(link.label, "why")

        XCTAssertTrue(CanvasGraph.convertToParent(link, in: store.context))
        try store.context.save()
        XCTAssertTrue(note.parent === idea)
        XCTAssertEqual(note.parentLabel, "why")
        XCTAssertEqual(try store.count(CanvasLink.self), 0)
    }

    @MainActor
    func testLinkToAnAncestorFlipsInsteadOfMakingACycle() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let deep = CanvasGraph.addNode(.idea, to: new.canvas, parent: idea, at: .zero, in: store.context)
        // A link from the deep Idea up to the root: the root can't go under its own descendant.
        let link = try XCTUnwrap(CanvasGraph.link(deep, to: new.root, in: store.context))
        try store.context.save()

        XCTAssertTrue(CanvasGraph.convertToParent(link, in: store.context))
        try store.context.save()
        XCTAssertNil(new.root.parent)
        XCTAssertTrue(deep.parent === new.root)
    }

    @MainActor
    func testEmptyLabelClears() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let a = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let b = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let link = try XCTUnwrap(CanvasGraph.link(a, to: b, label: "contrast", in: store.context))
        CanvasGraph.setLabel("   ", link: link)
        XCTAssertNil(link.label)
    }

    func testHitTestingPrefersTheIdeaOnTop() {
        let card = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: 0, y: 0, width: 200, height: 100), colorHex: nil, title: "")
        let idea = CanvasSnapshot.Node(id: UUID(), kind: .idea, rect: CGRect(x: 150, y: 50, width: 80, height: 80), colorHex: nil, title: "")
        let snapshot = CanvasSnapshot(nodes: [idea, card], edges: [])
        XCTAssertEqual(snapshot.node(at: CGPoint(x: 190, y: 90))?.id, idea.id, "inside both")
        XCTAssertEqual(snapshot.node(at: CGPoint(x: 155, y: 55))?.id, card.id, "inside the idea's box, outside its circle")
        XCTAssertNil(snapshot.node(at: CGPoint(x: 500, y: 500)))
    }

    func testLinesArePickedWithinTheTolerance() {
        let a = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: -10, y: -10, width: 20, height: 20), colorHex: nil, title: "")
        let b = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: 190, y: -10, width: 20, height: 20), colorHex: nil, title: "")
        let c = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: -10, y: 190, width: 20, height: 20), colorHex: nil, title: "")
        let across = CanvasSnapshot.Edge(id: "across", from: a.id, to: b.id, type: .relatesTo, label: nil)
        let down = CanvasSnapshot.Edge(id: "down", from: a.id, to: c.id, type: .belongsTo, label: nil)
        let snapshot = CanvasSnapshot(nodes: [a, b, c], edges: [across, down])

        XCTAssertEqual(snapshot.edge(near: CGPoint(x: 100, y: 4), tolerance: 6)?.id, "across")
        XCTAssertEqual(snapshot.edge(near: CGPoint(x: -3, y: 120), tolerance: 6)?.id, "down")
        XCTAssertNil(snapshot.edge(near: CGPoint(x: 100, y: 20), tolerance: 6))
        XCTAssertNil(snapshot.edge(near: CGPoint(x: 260, y: 0), tolerance: 6), "past the end of the line")
    }

    func testNeighborsFollowBothKindsOfLine() {
        let ids = (0..<4).map { _ in UUID() }
        let edges = [
            CanvasSnapshot.Edge(id: "1", from: ids[0], to: ids[1], type: .belongsTo, label: nil),
            CanvasSnapshot.Edge(id: "2", from: ids[2], to: ids[0], type: .relatesTo, label: nil),
        ]
        let snapshot = CanvasSnapshot(nodes: [], edges: edges)
        XCTAssertEqual(snapshot.neighbors(of: [ids[0]]), Set(ids[0...2]))
        XCTAssertEqual(snapshot.neighbors(of: [ids[3]]), [ids[3]])
    }
}
