import CoreGraphics
import SwiftData
import XCTest

final class ReferenceCanvasTests: XCTestCase {
    @MainActor
    func testDeletingAReferenceTakesItOffEveryCanvas() throws {
        let store = try TestStore()
        let reference = store.makeReference()
        let remix = store.makeReference(origin: .remix)
        remix.parent = reference
        let kept = store.makeReference()

        let first = CanvasGraph.makeCanvas(title: "A", in: store.context)
        let second = CanvasGraph.makeCanvas(title: "B", in: store.context)
        let card = CanvasGraph.addNode(.reference, to: first.canvas, parent: first.root, at: .zero, reference: reference, in: store.context)
        CanvasGraph.addNode(.note, to: first.canvas, parent: card, at: .zero, body: "about it", in: store.context)
        CanvasGraph.addNode(.prompt, to: second.canvas, parent: second.root, at: .zero, reference: remix, in: store.context)
        let keptCard = CanvasGraph.addNode(.reference, to: second.canvas, parent: second.root, at: .zero, reference: kept, in: store.context)
        let other = CanvasGraph.addNode(.note, to: first.canvas, parent: first.root, at: .zero, body: "next to it", in: store.context)
        XCTAssertNotNil(CanvasGraph.link(card, to: other, in: store.context))
        try store.context.save()

        XCTAssertEqual(reference.canvasCountWithRemixes, 2)

        Reference.delete(reference, in: store.context)

        XCTAssertEqual(try store.count(Reference.self), 1)
        XCTAssertEqual(try store.count(Canvas.self), 2)
        // Both roots, both notes and the kept card stay; the card's note moves up to the root.
        XCTAssertEqual(try store.count(CanvasNode.self), 5)
        XCTAssertEqual(try store.count(CanvasLink.self), 0)
        XCTAssertTrue(keptCard.reference === kept)
        let note = try store.context.fetch(FetchDescriptor<CanvasNode>()).first { $0.body == "about it" }
        XCTAssertTrue(note?.parent === first.root)
    }

    @MainActor
    func testCaptionPrefersTheWhyNoteThenTheMatchingRecipePart() throws {
        let store = try TestStore()
        let reference = store.makeReference(origin: .generated)
        reference.recipe = [
            RecipePart(kind: .subject, text: "ceramic bottle"),
            RecipePart(kind: .light, text: "harsh direct flash"),
        ]
        reference.why = [.light]
        XCTAssertEqual(reference.caption, "harsh direct flash")

        reference.why = [.type]
        XCTAssertEqual(reference.caption, "ceramic bottle")

        reference.whyNote = "the diagonal crop"
        XCTAssertEqual(reference.caption, "the diagonal crop")

        let bare = store.makeReference(origin: .mine)
        bare.why = [.texture]
        XCTAssertEqual(bare.caption, "Mine · Texture")
    }

    @MainActor
    func testExampleCanvasMatchesTheSpec() throws {
        let store = try TestStore()
        let references = (0..<12).map { _ in store.makeReference(origin: .generated) }
        references[0].recipe = [RecipePart(kind: .subject, text: "bottle")]
        references[11].recipe = [RecipePart(kind: .subject, text: "coat")]
        try store.context.save()

        let canvas = SeedData.makeExampleCanvas(from: references, in: store.context)
        try store.context.save()

        let nodes = canvas.nodes
        XCTAssertEqual(nodes.count, 13)
        XCTAssertEqual(canvas.links.count, 1)
        XCTAssertEqual(canvas.categories.count, 4)
        XCTAssertEqual(canvas.roots.map(\.title), ["Product photography look"])

        let subIdeas = nodes.filter { $0.isIdea && !$0.isRoot }
        XCTAssertEqual(Set(subIdeas.compactMap(\.title)), ["Light", "Composition"])
        XCTAssertTrue(subIdeas.allSatisfy { $0.ideaDepth == 1 })

        XCTAssertEqual(nodes.filter { $0.kind == .reference }.count, 6)
        let prompts = nodes.filter { $0.kind == .prompt }
        XCTAssertEqual(Set(prompts.compactMap { $0.reference?.purpose }), [.image, .text])
        XCTAssertEqual(nodes.filter { $0.kind == .note }.count, 2)

        let textPrompt = prompts.first { $0.reference?.purpose == .text }?.reference
        XCTAssertEqual(textPrompt?.hasMedia, false)
        XCTAssertEqual(references[0].purpose, .image, "seeded before purposes existed")

        let link = try XCTUnwrap(canvas.links.first)
        XCTAssertEqual(Set([link.from?.title, link.to?.title].compactMap { $0 }), ["Light", "Composition"])
        XCTAssertEqual(link.label, "shadows shape the frame")
    }
}
