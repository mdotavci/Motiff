import CoreGraphics
import SwiftData
import XCTest

/// Step 20: a board written out for an AI.
final class AIPackTests: XCTestCase {
    @MainActor
    func testTheExampleBoardReadsInMindMapOrderWithNumberedPictures() throws {
        let store = try TestStore()
        let references = (0..<12).map { _ in store.makeReference(origin: .generated) }
        references[11].promptRaw = "model in structured coat --ar 4:5"
        references[11].model = "Midjourney"
        let board = SeedData.makeExampleCanvas(from: references, in: store.context)
        try store.context.save()

        let pack = AIPack.make(from: board, instruction: "You are my creative director.")
        let text = pack.markdown

        XCTAssertTrue(text.hasPrefix("# Product photography look\n\nYou are my creative director."))
        let light = try XCTUnwrap(text.range(of: "### Light"))
        let composition = try XCTUnwrap(text.range(of: "### Composition"))
        XCTAssertLessThan(light.lowerBound, composition.lowerBound)
        XCTAssertTrue(text.contains("**Prompt for Midjourney**"))
        XCTAssertTrue(text.contains("model in structured coat --ar 4:5"))
        XCTAssertTrue(text.contains("> Hard light reads confident; soft light reads calm."))
        XCTAssertTrue(text.contains("## Connections\n- Light → Composition (shadows shape the frame)"))

        XCTAssertEqual(pack.pictures.map(\.number), Array(1...pack.pictures.count))
        for picture in pack.pictures {
            XCTAssertTrue(text.contains("[Image \(picture.number)"), "every picture is named in the text")
        }
        XCTAssertEqual(pack.pictures.first?.exportName, "01.png")
    }

    @MainActor
    func testLooseThingsComeAfterTopToBottom() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "Mood", rootTitle: "Mood", in: store.context)
        CanvasGraph.addSticky(to: new.canvas, at: CGPoint(x: 0, y: 600), text: "Second", in: store.context)
        CanvasGraph.addSticky(to: new.canvas, at: CGPoint(x: 0, y: 300), text: "First", in: store.context)
        CanvasGraph.addLine(from: .zero, to: CGPoint(x: 100, y: 0), on: new.canvas, in: store.context)

        let text = AIPack.make(from: new.canvas).markdown
        let board = try XCTUnwrap(text.range(of: "## On the board"))
        let first = try XCTUnwrap(text.range(of: "> First"))
        let second = try XCTUnwrap(text.range(of: "> Second"))
        XCTAssertLessThan(board.lowerBound, first.lowerBound)
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        XCTAssertFalse(text.contains("Arrow"), "free arrows are drawing, not content")
    }

    @MainActor
    func testJustTheSelectionAndWhatsAttachedToIt() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "Mood", rootTitle: "Mood", in: store.context)
        let prompt = CanvasGraph.addNode(.prompt, to: new.canvas, at: CGPoint(x: 300, y: 0), reference: store.makeReference(), in: store.context)
        prompt.reference?.promptRaw = "soft light"
        let example = store.makeReference()
        CanvasGraph.addNode(.reference, to: new.canvas, parent: prompt, at: CGPoint(x: 500, y: 0), reference: example, in: store.context)
        CanvasGraph.addSticky(to: new.canvas, at: CGPoint(x: -300, y: 0), text: "Not this", in: store.context)

        let pack = AIPack.make(from: new.canvas, only: [prompt.id])
        XCTAssertTrue(pack.markdown.contains("soft light"))
        XCTAssertFalse(pack.markdown.contains("Not this"))
        XCTAssertEqual(pack.pictures.count, 2, "the prompt's own picture and the example under it")
    }

    func testExportedFileNamesAreSafe() {
        XCTAssertEqual(AIPack.safeName("Spring / Summer: 2026"), "Spring - Summer- 2026")
        XCTAssertEqual(AIPack.safeName("   "), "Board")
    }
}
