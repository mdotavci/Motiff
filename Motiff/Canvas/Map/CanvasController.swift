import CoreGraphics
import Foundation
import Observation

/// State for one open Canvas: what the Map shows (`snapshot`), where it's looking (`camera`),
/// and how big the view is. One per Canvas view; the Canvas itself stays the source of truth.
@MainActor
@Observable
final class CanvasController {
    let canvas: Canvas

    private(set) var camera: CanvasCamera
    private(set) var viewSize: CGSize = .zero
    private(set) var snapshot: CanvasSnapshot = .empty
    /// The pointer over the map, in view points; nil when it's elsewhere.
    var pointer: CGPoint?

    @ObservationIgnored private var nodesByID: [UUID: CanvasNode] = [:]
    @ObservationIgnored private var needsFit: Bool
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored var eventMonitor: Any?

    /// How far a ⌘+ / ⌘− step zooms.
    static let zoomStep: CGFloat = 1.25
    /// Room around the view edge where nodes are kept mounted, in view points.
    static let cullMargin: CGFloat = 200

    init(canvas: Canvas) {
        self.canvas = canvas
        let viewport = canvas.viewport
        camera = CanvasCamera(center: CGPoint(x: viewport.centerX, y: viewport.centerY), zoom: viewport.zoom)
        // A Canvas that has never been looked at opens fitted to its content.
        needsFit = viewport == .initial
    }

    /// Rebuilds the snapshot from the Canvas. Call when it changes (`updatedAt`).
    func reload() {
        snapshot = CanvasSnapshot(canvas: canvas)
        nodesByID = Dictionary(canvas.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        fitIfNeeded()
    }

    func node(_ id: UUID) -> CanvasNode? {
        nodesByID[id]
    }

    /// Nodes on screen or near it. Only these get views.
    var visibleNodes: [CanvasSnapshot.Node] {
        guard viewSize.width > 0, viewSize.height > 0 else { return [] }
        let margin = Self.cullMargin / camera.zoom
        return snapshot.nodes(intersecting: camera.visibleRect(in: viewSize).insetBy(dx: -margin, dy: -margin))
    }

    func setViewSize(_ size: CGSize) {
        viewSize = size
        fitIfNeeded()
    }

    // MARK: Moving the camera

    func pan(by screenDelta: CGSize) {
        move(to: camera.panned(by: screenDelta))
    }

    /// Zooms around `anchor` (a view point), or around the middle of the view.
    func zoom(by factor: CGFloat, at anchor: CGPoint? = nil) {
        let point = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        move(to: camera.zoomed(by: factor, anchor: point, in: viewSize))
    }

    func zoomIn() { zoom(by: Self.zoomStep) }
    func zoomOut() { zoom(by: 1 / Self.zoomStep) }

    func fitToContent() {
        guard viewSize.width > 0, !snapshot.nodes.isEmpty else { return }
        move(to: .fitting(snapshot.bounds, in: viewSize))
    }

    private func fitIfNeeded() {
        guard needsFit, viewSize.width > 0, !snapshot.nodes.isEmpty else { return }
        needsFit = false
        fitToContent()
    }

    private func move(to newCamera: CanvasCamera) {
        guard newCamera != camera else { return }
        camera = newCamera
        scheduleViewportSave()
    }

    /// Writes the viewport back half a second after the camera stops, so reopening the
    /// Canvas shows the same place without a write per frame.
    private func scheduleViewportSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !self.canvas.isDeleted else { return }
            let camera = self.camera
            self.canvas.viewport = CanvasViewport(centerX: camera.center.x, centerY: camera.center.y, zoom: camera.zoom)
        }
    }
}
