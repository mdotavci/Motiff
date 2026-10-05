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
        /// For filtering by category and by prompt purpose.
        var categoryID: UUID? = nil
        var purpose: PromptPurpose? = nil

        var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

        /// Inside the circle for an Idea, the rectangle for a card.
        func contains(_ point: CGPoint) -> Bool {
            guard kind == .idea else { return rect.contains(point) }
            let dx = point.x - center.x
            let dy = point.y - center.y
            return dx * dx + dy * dy <= (rect.width / 2) * (rect.width / 2)
        }

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
        for node in canvas.nodes where !node.isDeleted {
            let size = CanvasLayout.size(of: node)
            nodes.append(Node(
                id: node.id,
                kind: node.kind,
                rect: CGRect(x: node.x - size.width / 2, y: node.y - size.height / 2, width: size.width, height: size.height),
                colorHex: node.category?.colorHex,
                title: node.displayTitle,
                categoryID: node.category?.id,
                purpose: node.reference?.purpose
            ))
            if let parent = node.parent, !parent.isDeleted {
                edges.append(Edge(id: "parent-\(node.id)", from: parent.id, to: node.id, type: .belongsTo, label: node.parentLabel))
            }
        }
        for link in canvas.links {
            guard !link.isDeleted, let from = link.from, let to = link.to else { continue }
            edges.append(Edge(id: link.id.uuidString, from: from.id, to: to.id, type: .relatesTo, label: link.label))
        }
        self.init(nodes: nodes, edges: edges)
    }

    /// The same Canvas with some nodes shifted, for drawing a drag before it's committed.
    func moving(_ ids: Set<UUID>, by offset: CGSize) -> CanvasSnapshot {
        guard !ids.isEmpty, offset != .zero else { return self }
        let moved = nodes.map { node in
            guard ids.contains(node.id) else { return node }
            return Node(
                id: node.id,
                kind: node.kind,
                rect: node.rect.offsetBy(dx: offset.width, dy: offset.height),
                colorHex: node.colorHex,
                title: node.title,
                categoryID: node.categoryID,
                purpose: node.purpose
            )
        }
        return CanvasSnapshot(nodes: moved, edges: edges)
    }

    func node(_ id: UUID) -> Node? {
        index[id].map { nodes[$0] }
    }

    func edge(_ id: String) -> Edge? {
        edges.first { $0.id == id }
    }

    /// The top-most node at a canvas point. Ideas draw on top, so they win over a card under them.
    func node(at point: CGPoint) -> Node? {
        nodes.last(where: { $0.contains(point) })
    }

    /// Where a line is drawn, in canvas points: from outline to outline.
    func segment(of edge: Edge) -> (start: CGPoint, end: CGPoint)? {
        guard let from = node(edge.from), let to = node(edge.to) else { return nil }
        return (from.edgePoint(toward: to.center), to.edgePoint(toward: from.center))
    }

    /// The line closest to a canvas point, if it's within `tolerance` (canvas points).
    func edge(near point: CGPoint, tolerance: CGFloat) -> Edge? {
        var best: (edge: Edge, distance: CGFloat)?
        for edge in edges {
            guard let segment = segment(of: edge) else { continue }
            let distance = Self.distance(from: point, toSegment: segment.start, segment.end)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (edge, distance)
            }
        }
        return best?.edge
    }

    /// Nodes in any of `categories` (all, if empty) whose prompt purpose is any of `purposes`
    /// (all, if empty). Nil when neither filter is on.
    func matching(categories: Set<UUID>, purposes: Set<PromptPurpose>) -> Set<UUID>? {
        guard !categories.isEmpty || !purposes.isEmpty else { return nil }
        return Set(nodes.filter { node in
            (categories.isEmpty || node.categoryID.map { categories.contains($0) } == true)
                && (purposes.isEmpty || node.purpose.map { purposes.contains($0) } == true)
        }.map(\.id))
    }

    /// The given nodes and everything one line away from them.
    func neighbors(of ids: Set<UUID>) -> Set<UUID> {
        var result = ids
        for edge in edges {
            if ids.contains(edge.from) { result.insert(edge.to) }
            if ids.contains(edge.to) { result.insert(edge.from) }
        }
        return result
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        var t: CGFloat = 0
        if lengthSquared > 0 {
            t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        }
        let x = a.x + t * dx - point.x
        let y = a.y + t * dy - point.y
        return (x * x + y * y).squareRoot()
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
