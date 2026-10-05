import CoreGraphics
import SwiftData
import XCTest

final class CanvasGraphTests: XCTestCase {
    @MainActor
    func testNewCanvasHasOneRootAndSixCategories() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "Brief", rootTitle: "Idea", in: store.context)
        try store.context.save()

        XCTAssertEqual(new.canvas.nodes.count, 1)
        XCTAssertTrue(new.root.isRoot)
        XCTAssertEqual(new.root.kind, .idea)
        XCTAssertEqual(new.canvas.roots.map(\.title), ["Idea"])
        XCTAssertEqual(new.canvas.sortedCategories.map(\.name), CanvasCategory.defaults.map(\.name))
        XCTAssertEqual(new.canvas.sortedCategories.map(\.order), Array(0..<6))
    }

    @MainActor
    func testChildTakesItsParentsCategory() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, category: new.categories[2], in: store.context)
        let note = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertTrue(note.category === new.categories[2])
        XCTAssertEqual(idea.ideaDepth, 1)
    }

    @MainActor
    func testSetParentRefusesCycles() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let card = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertFalse(CanvasGraph.setParent(new.root, to: card, in: store.context), "root under its own grandchild")
        XCTAssertFalse(CanvasGraph.setParent(idea, to: idea, in: store.context), "a node under itself")
        XCTAssertNil(new.root.parent)
        XCTAssertTrue(card.parent === idea)

        XCTAssertTrue(CanvasGraph.setParent(card, to: new.root, label: "direct", in: store.context))
        XCTAssertTrue(card.parent === new.root)
        XCTAssertEqual(card.parentLabel, "direct")
    }

    @MainActor
    func testSetParentRefusesAnotherCanvas() throws {
        let store = try TestStore()
        let first = CanvasGraph.makeCanvas(title: "A", in: store.context)
        let second = CanvasGraph.makeCanvas(title: "B", in: store.context)
        let note = CanvasGraph.addNode(.note, to: first.canvas, at: .zero, in: store.context)
        try store.context.save()

        XCTAssertFalse(CanvasGraph.setParent(note, to: second.root, in: store.context))
        XCTAssertNil(note.parent)
    }

    @MainActor
    func testDeletingANodeMovesItsChildrenUp() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let first = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        let second = CanvasGraph.addNode(.note, to: new.canvas, parent: idea, at: .zero, in: store.context)
        try store.context.save()

        CanvasGraph.deleteNode(idea, in: store.context)
        try store.context.save()

        XCTAssertTrue(first.parent === new.root)
        XCTAssertTrue(second.parent === new.root)
        XCTAssertEqual(try store.count(CanvasNode.self), 3)
    }

    @MainActor
    func testDeletingABranchTakesEverythingUnderIt() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let subIdea = CanvasGraph.addNode(.idea, to: new.canvas, parent: idea, at: .zero, in: store.context)
        CanvasGraph.addNode(.note, to: new.canvas, parent: subIdea, at: .zero, in: store.context)
        let other = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        CanvasGraph.link(other, to: subIdea, in: store.context)
        try store.context.save()

        CanvasGraph.deleteBranch(idea, in: store.context)
        try store.context.save()

        XCTAssertEqual(try store.count(CanvasNode.self), 2, "root and the other note")
        XCTAssertEqual(try store.count(CanvasLink.self), 0, "the link into the branch goes with it")
    }

    @MainActor
    func testLinksAreUniqueAndSkipParents() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let light = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let composition = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)

        XCTAssertNotNil(CanvasGraph.link(light, to: composition, label: "contrast", in: store.context))
        XCTAssertNil(CanvasGraph.link(composition, to: light, in: store.context), "already linked the other way")
        XCTAssertNil(CanvasGraph.link(light, to: light, in: store.context), "to itself")
        XCTAssertNil(CanvasGraph.link(light, to: new.root, in: store.context), "it already belongs to the root")
        try store.context.save()

        XCTAssertEqual(try store.count(CanvasLink.self), 1)
        XCTAssertEqual(CanvasGraph.link(between: composition, and: light)?.label, "contrast")
    }

    @MainActor
    func testReparentingOntoALinkedNodeDropsTheLink() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        let note = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, in: store.context)
        CanvasGraph.link(note, to: idea, in: store.context)
        try store.context.save()

        XCTAssertTrue(CanvasGraph.setParent(note, to: idea, in: store.context))
        try store.context.save()

        XCTAssertEqual(try store.count(CanvasLink.self), 0)
    }

    @MainActor
    func testDeletingACanvasKeepsItsReferences() throws {
        let store = try TestStore()
        let reference = store.makeReference()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        CanvasGraph.addNode(.reference, to: new.canvas, parent: new.root, at: .zero, reference: reference, in: store.context)
        try store.context.save()

        CanvasGraph.deleteCanvas(new.canvas, in: store.context)
        try store.context.save()

        XCTAssertEqual(try store.count(Canvas.self), 0)
        XCTAssertEqual(try store.count(CanvasNode.self), 0)
        XCTAssertEqual(try store.count(CanvasCategory.self), 0)
        XCTAssertEqual(try store.count(Reference.self), 1)
    }
}
