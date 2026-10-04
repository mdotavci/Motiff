import CoreGraphics
import Foundation

/// A Canvas flattened into plain values: where every node is and which lines join them.
/// Drawing and culling read this, never the SwiftData objects, so a frame costs no fetches.
struct CanvasSnapshot: Equatable, Sendable {
    struct Node: Identifiable, Equatable, Sendable {
        let id: UUID
        let kind: NodeKind
        /// In canvas points, centered on the node's position.
        let rect: CGRect
        let colorHex: String?
        let title: String

        var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

        /// Where a line from this node's center toward `target` leaves its outline:
        /// the circle for an Idea, the rectangle for a card.
        func edgePoint(toward target: CGPoint) -> CGPoint {
            let dx = target.x - center.x
            let dy = target.y - center.y
            guard dx != 0 || dy != 0 else { return center }
            let scale: CGFloat
            if kind == .idea {
                scale = (rect.width / 2) / (dx * dx + dy * dy).squareRoot()
            } else {
                let toSide = dx == 0 ? .infinity : (rect.width / 2) / abs(dx)
                let toTop = dy == 0 ? .infinity : (rect.height / 2) / abs(dy)
                scale = min(toSide, toTop)
            }
            return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        }
    }

    struct Edge: Identifiable, Equatable, Sendable {
        let id: String
        let from: UUID
        let to: UUID
        let type: LinkType
        let label: String?
    }

    /// Cards first, Ideas last, so circles draw on top.
    let nodes: [Node]
    let edges: [Edge]
    private let index: [UUID: Int]

    static let empty = CanvasSnapshot(nodes: [], edges: [])

    init(nodes: [Node], edges: [Edge]) {
        let sorted = nodes.sorted { ($0.kind == .idea ? 1 : 0) < ($1.kind == .idea ? 1 : 0) }
        self.nodes = sorted
        self.edges = edges
        self.index = Dictionary(sorted.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @MainActor
    init(canvas: Canvas) {
        var nodes: [Node] = []
        var edges: [Edge] = []
        for node in canvas.nodes {
            let size = CanvasLayout.size(of: node)
            nodes.append(Node(
                id: node.id,
                kind: node.kind,
                rect: CGRect(x: node.x - size.width / 2, y: node.y - size.height / 2, width: size.width, height: size.height),
                colorHex: node.category?.colorHex,
                title: node.displayTitle
            ))
            if let parent = node.parent {
                edges.append(Edge(id: "parent-\(node.id)", from: parent.id, to: node.id, type: .belongsTo, label: node.parentLabel))
            }
        }
        for link in canvas.links {
            guard let from = link.from, let to = link.to else { continue }
            edges.append(Edge(id: link.id.uuidString, from: from.id, to: to.id, type: .relatesTo, label: link.label))
        }
        self.init(nodes: nodes, edges: edges)
    }

    func node(_ id: UUID) -> Node? {
        index[id].map { nodes[$0] }
    }

    /// Everything on the Canvas, or `.null` when it's empty.
    var bounds: CGRect {
        nodes.reduce(CGRect.null) { $0.union($1.rect) }
    }

    func nodes(intersecting rect: CGRect) -> [Node] {
        nodes.filter { $0.rect.intersects(rect) }
    }

    static func == (lhs: CanvasSnapshot, rhs: CanvasSnapshot) -> Bool {
        lhs.nodes == rhs.nodes && lhs.edges == rhs.edges
    }
}
