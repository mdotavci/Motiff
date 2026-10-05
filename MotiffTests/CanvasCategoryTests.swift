import CoreGraphics
import SwiftData
import XCTest

final class CanvasCategoryTests: XCTestCase {
    @MainActor
    func testAddedCategoryTakesAnUnusedSwatchAndGoesLast() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let added = CanvasGraph.addCategory(to: new.canvas, in: store.context)
        try store.context.save()

        XCTAssertFalse(new.categories.map(\.colorHex).contains(added.colorHex))
        XCTAssertTrue(CanvasCategory.swatches.contains { $0.hex == added.colorHex })
        XCTAssertTrue(new.canvas.sortedCategories.last === added)
    }

    @MainActor
    func testMovingKeepsOrdersInSequence() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let third = new.canvas.sortedCategories[2]
        CanvasGraph.moveCategory(third, by: -1)
        CanvasGraph.moveCategory(third, by: -1)
        CanvasGraph.moveCategory(third, by: -1)

        let ordered = new.canvas.sortedCategories
        XCTAssertTrue(ordered.first === third)
        XCTAssertEqual(ordered.map(\.order), Array(0..<ordered.count))
    }

    @MainActor
    func testDeletingACategoryKeepsItsNodes() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let category = new.categories[1]
        let note = CanvasGraph.addNode(.note, to: new.canvas, parent: new.root, at: .zero, category: category, in: store.context)
        try store.context.save()

        CanvasGraph.deleteCategory(category, in: store.context)
        try store.context.save()

        XCTAssertNil(note.category)
        XCTAssertEqual(try store.count(CanvasNode.self), 2)
        XCTAssertEqual(new.canvas.sortedCategories.map(\.order), Array(0..<5))
    }

    @MainActor
    func testColorsComeOnlyFromTheSwatches() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let category = new.categories[0]
        CanvasGraph.setColor(category, to: "#E2231A")
        XCTAssertEqual(category.colorHex, CanvasCategory.defaults[0].hex, "focus red is refused")
        CanvasGraph.setColor(category, to: "#8E5A8A")
        XCTAssertEqual(category.colorHex, "#8E5A8A")
    }

    func testFiltersMatchCategoryAndPurposeTogether() {
        let light = UUID()
        let blue = UUID()
        func node(_ category: UUID?, _ purpose: PromptPurpose?) -> CanvasSnapshot.Node {
            CanvasSnapshot.Node(
                id: UUID(), kind: .prompt, rect: .zero, colorHex: nil, title: "",
                categoryID: category, purpose: purpose
            )
        }
        let a = node(light, .image)
        let b = node(light, .text)
        let c = node(blue, .image)
        let snapshot = CanvasSnapshot(nodes: [a, b, c], edges: [])

        XCTAssertNil(snapshot.matching(categories: [], purposes: []))
        XCTAssertEqual(snapshot.matching(categories: [light], purposes: []), [a.id, b.id])
        XCTAssertEqual(snapshot.matching(categories: [], purposes: [.image]), [a.id, c.id])
        XCTAssertEqual(snapshot.matching(categories: [light], purposes: [.image]), [a.id])
    }
}
