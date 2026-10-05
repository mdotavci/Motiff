import Foundation

/// The Canvas as an indented list: each root and everything under it, depth first in sibling
/// order, then the loose nodes. Collapsed nodes hide what's under them.
enum CanvasOutline {
    struct Row: Identifiable, Equatable, Sendable {
        let id: UUID
        let depth: Int
        let hasChildren: Bool
    }

    /// Deeper than this is treated as a loop and not followed.
    private static let maxDepth = 200

    @MainActor
    static func rows(of canvas: Canvas, collapsed: Set<UUID>) -> [Row] {
        var rows: [Row] = []
        func add(_ node: CanvasNode, depth: Int) {
            guard !node.isDeleted, depth < maxDepth else { return }
            let children = node.sortedChildren.filter { !$0.isDeleted }
            rows.append(Row(id: node.id, depth: depth, hasChildren: !children.isEmpty))
            guard !collapsed.contains(node.id) else { return }
            for child in children { add(child, depth: depth + 1) }
        }
        for root in canvas.roots { add(root, depth: 0) }
        for loose in canvas.unattachedNodes { add(loose, depth: 0) }
        return rows
    }
}
