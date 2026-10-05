import CoreGraphics
import SwiftData
import XCTest

final class CanvasFindTests: XCTestCase {
    func testFuzzyMatchRanking() {
        XCTAssertNil(FuzzyMatch.score("xyz", in: "Light"))
        XCTAssertEqual(FuzzyMatch.score("", in: "anything"), 0)
        let exact = FuzzyMatch.score("light", in: "Light") ?? .min
        let inside = FuzzyMatch.score("light", in: "Hard light reads confident") ?? .min
        XCTAssertGreaterThan(exact, inside, "the start of the text beats the middle")
        let wordStarts = FuzzyMatch.score("hl", in: "Hard light") ?? .min
        let scattered = FuzzyMatch.score("hl", in: "shall") ?? .min
        XCTAssertGreaterThan(wordStarts, scattered, "word starts beat scattered letters")
        XCTAssertNotNil(FuzzyMatch.score("photo look", in: "Product photography look"), "spaces in the query are ignored")
        XCTAssertNotNil(FuzzyMatch.score("cafe", in: "Café"), "accents are ignored")
    }

    @MainActor
    func testSearchFindsAcrossKindsInOutlineOrder() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", rootTitle: "Root", in: store.context)
        let idea = CanvasGraph.addNode(.idea, to: new.canvas, parent: new.root, at: .zero, title: "Window light", in: store.context)
        let prompt = store.makeReference(origin: .generated)
        prompt.promptRaw = "bottle on stone, hard LIGHT from the left"
        let card = CanvasGraph.addNode(.prompt, to: new.canvas, parent: idea, at: .zero, reference: prompt, in: store.context)
        CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, body: "Nothing here", in: store.context)
        let link = CanvasGraph.addNode(.link, to: new.canvas, parent: new.root, at: .zero, title: "Lighting guide", in: store.context)
        try store.context.save()

        XCTAssertEqual(CanvasSearch.matches(in: new.canvas, query: " light "), [idea.id, card.id, link.id])
        XCTAssertEqual(CanvasSearch.matches(in: new.canvas, query: ""), [])
    }

    @MainActor
    func testStressCanvasHasFiveHundredNodesThatDontOverlap() throws {
        let store = try TestStore()
        let canvas = CanvasStress.make(in: store.context)
        XCTAssertEqual(canvas.nodes.count, CanvasStress.total)

        // Every pair among a sample, plus each sampled node against all others.
        let rects = canvas.nodes.map { CanvasGraph.rect(of: $0) }
        for i in stride(from: 0, to: rects.count, by: 25) {
            for j in rects.indices where j != i {
                XCTAssertFalse(rects[i].insetBy(dx: 1, dy: 1).intersects(rects[j].insetBy(dx: 1, dy: 1)), "\(i) overlaps \(j)")
            }
        }
    }
}
