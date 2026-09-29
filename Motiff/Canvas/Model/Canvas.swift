import Foundation
import SwiftData

/// A spatial idea map: Ideas, cards and the links between them. A Canvas is a file, like a
/// document. Its cards point at the same References the Library shows, never copies.
///
/// Named after the spec. In files that also import SwiftUI, the drawing view is `SwiftUI.Canvas`.
@Model
final class Canvas {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    /// Bumped by `CanvasGraph` on every change.
    var updatedAt: Date = Date.now

    // MARK: Viewport (see `viewport`)

    var viewportCenterX: Double = 0
    var viewportCenterY: Double = 0
    var viewportZoom: Double = 1

    @Relationship(deleteRule: .cascade, inverse: \CanvasNode.canvas) var nodes: [CanvasNode] = []
    @Relationship(deleteRule: .cascade, inverse: \CanvasLink.canvas) var links: [CanvasLink] = []
    @Relationship(deleteRule: .cascade, inverse: \CanvasCategory.canvas) var categories: [CanvasCategory] = []

    init(title: String) {
        self.title = title
    }
}

extension Canvas {
    var displayTitle: String {
        title.isEmpty ? "Untitled canvas" : title
    }

    var viewport: CanvasViewport {
        get { CanvasViewport(centerX: viewportCenterX, centerY: viewportCenterY, zoom: viewportZoom) }
        set {
            viewportCenterX = newValue.centerX
            viewportCenterY = newValue.centerY
            viewportZoom = newValue.zoom
        }
    }

    /// Categories in legend order.
    var sortedCategories: [CanvasCategory] {
        categories.sorted { $0.order < $1.order }
    }

    /// The Canvas's root Ideas. Normally one; more if a root was pasted in from elsewhere.
    var roots: [CanvasNode] {
        nodes.filter(\.isRoot).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Nodes that don't belong to anything and aren't a root: loose cards and ideas.
    var unattachedNodes: [CanvasNode] {
        nodes.filter { $0.parent == nil && !$0.isRoot }.sorted { $0.sortIndex < $1.sortIndex }
    }
}
