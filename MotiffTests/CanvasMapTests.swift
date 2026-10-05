import CoreGraphics
import SwiftData
import XCTest

final class CanvasMapTests: XCTestCase {
    private let view = CGSize(width: 800, height: 600)

    func testScreenAndCanvasPointsRoundTrip() {
        let camera = CanvasCamera(center: CGPoint(x: 100, y: 50), zoom: 2)
        let point = CGPoint(x: 130, y: 70)
        let back = camera.canvasPoint(camera.screenPoint(point, in: view), in: view)
        XCTAssertEqual(back.x, point.x, accuracy: 0.001)
        XCTAssertEqual(back.y, point.y, accuracy: 0.001)
        XCTAssertEqual(camera.screenPoint(camera.center, in: view), CGPoint(x: 400, y: 300))
    }

    func testZoomKeepsThePointUnderThePointer() {
        let camera = CanvasCamera(center: CGPoint(x: -40, y: 25), zoom: 0.8)
        let pointer = CGPoint(x: 610, y: 120)
        let before = camera.canvasPoint(pointer, in: view)
        let zoomed = camera.zoomed(by: 1.5, anchor: pointer, in: view)
        let after = zoomed.canvasPoint(pointer, in: view)
        XCTAssertEqual(zoomed.zoom, 1.2, accuracy: 0.0001)
        XCTAssertEqual(after.x, before.x, accuracy: 0.001)
        XCTAssertEqual(after.y, before.y, accuracy: 0.001)
    }

    func testZoomStaysInRange() {
        XCTAssertEqual(CanvasCamera(center: .zero, zoom: 50).zoom, CanvasCamera.zoomRange.upperBound)
        let far = CanvasCamera.initial.zoomed(by: 0.0001, anchor: .zero, in: view)
        XCTAssertEqual(far.zoom, CanvasCamera.zoomRange.lowerBound)
    }

    func testPanningMovesContentWithTheFingers() {
        let camera = CanvasCamera(center: .zero, zoom: 2)
        let panned = camera.panned(by: CGSize(width: 100, height: -40))
        XCTAssertEqual(panned.screenPoint(.zero, in: view), CGPoint(x: 500, y: 260))
    }

    func testFitShowsEverythingWithoutZoomingPastOneHundredPercent() {
        let content = CGRect(x: -700, y: -900, width: 1500, height: 1100)
        let camera = CanvasCamera.fitting(content, in: view)
        let onScreen = CGRect(
            origin: camera.screenPoint(content.origin, in: view),
            size: CGSize(width: content.width * camera.zoom, height: content.height * camera.zoom)
        )
        XCTAssertTrue(CGRect(origin: .zero, size: view).contains(onScreen))

        let small = CanvasCamera.fitting(CGRect(x: 0, y: 0, width: 50, height: 50), in: view)
        XCTAssertEqual(small.zoom, 1)
    }

    func testNodeSizesFollowTheDesign() {
        func idea(_ level: Int) -> CGFloat {
            CanvasLayout.size(kind: .idea, ideaLevel: level, heightOverWidth: 1).width
        }
        XCTAssertEqual([idea(0), idea(1), idea(2), idea(5)], [128, 88, 64, 64])
        XCTAssertEqual(CanvasLayout.ideaLevel(isRoot: true, depth: 0), 0)
        XCTAssertEqual(CanvasLayout.ideaLevel(isRoot: false, depth: 0), 1, "a loose Idea is sub-idea size")
        XCTAssertEqual(CanvasLayout.size(kind: .reference, ideaLevel: 0, heightOverWidth: 1.25), CGSize(width: 176, height: 262))
        XCTAssertEqual(CanvasLayout.size(kind: .note, ideaLevel: 0, heightOverWidth: 1), CGSize(width: 224, height: 112))
        let resized = CGSize(width: 300, height: 90)
        XCTAssertEqual(CanvasLayout.size(kind: .note, ideaLevel: 0, heightOverWidth: 1, override: resized), resized)
    }

    func testEdgesLeaveCirclesAndCardsAtTheirOutline() {
        let idea = CanvasSnapshot.Node(id: UUID(), kind: .idea, rect: CGRect(x: -44, y: -44, width: 88, height: 88), colorHex: nil, title: "")
        let point = idea.edgePoint(toward: CGPoint(x: 300, y: 400))
        XCTAssertEqual((point.x * point.x + point.y * point.y).squareRoot(), 44, accuracy: 0.001)

        let card = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: 0, y: 0, width: 200, height: 100), colorHex: nil, title: "")
        let below = card.edgePoint(toward: CGPoint(x: 100, y: 500))
        XCTAssertEqual(below.x, 100, accuracy: 0.001)
        XCTAssertEqual(below.y, 100, accuracy: 0.001)
        let left = card.edgePoint(toward: CGPoint(x: -900, y: 50))
        XCTAssertEqual(left.x, 0, accuracy: 0.001)
        XCTAssertEqual(left.y, 50, accuracy: 0.001)
    }

    @MainActor
    func testExampleCanvasSnapshot() throws {
        let store = try TestStore()
        let references = (0..<12).map { _ in store.makeReference(origin: .generated) }
        let canvas = SeedData.makeExampleCanvas(from: references, in: store.context)
        try store.context.save()

        let snapshot = CanvasSnapshot(canvas: canvas)
        XCTAssertEqual(snapshot.nodes.count, 13)
        XCTAssertEqual(snapshot.edges.filter { $0.type == .belongsTo }.count, 12)
        XCTAssertEqual(snapshot.edges.filter { $0.type == .relatesTo }.count, 1)
        XCTAssertEqual(snapshot.nodes.last?.kind, .idea, "Ideas draw last, on top")

        let bounds = snapshot.bounds
        XCTAssertTrue(snapshot.nodes.allSatisfy { bounds.contains($0.rect) })
        XCTAssertTrue(snapshot.nodes(intersecting: CGRect(x: 50_000, y: 50_000, width: 10, height: 10)).isEmpty)
        XCTAssertEqual(snapshot.nodes(intersecting: bounds).count, 13)

        let root = try XCTUnwrap(canvas.roots.first)
        XCTAssertEqual(snapshot.node(root.id)?.rect.size, CGSize(width: 128, height: 128))
    }

    func testDraggingShiftsOnlyTheDraggedNodes() {
        let a = CanvasSnapshot.Node(id: UUID(), kind: .note, rect: CGRect(x: 0, y: 0, width: 10, height: 10), colorHex: nil, title: "a")
        let b = CanvasSnapshot.Node(id: UUID(), kind: .idea, rect: CGRect(x: 50, y: 0, width: 10, height: 10), colorHex: nil, title: "b")
        let snapshot = CanvasSnapshot(nodes: [a, b], edges: [])
        let moved = snapshot.moving([a.id], by: CGSize(width: 5, height: -5))
        XCTAssertEqual(moved.node(a.id)?.rect.origin, CGPoint(x: 5, y: -5))
        XCTAssertEqual(moved.node(b.id)?.rect, b.rect)
        XCTAssertEqual(snapshot.moving([], by: CGSize(width: 5, height: 5)), snapshot)
    }
}
