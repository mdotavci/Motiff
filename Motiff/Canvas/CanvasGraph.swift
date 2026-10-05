import CoreGraphics
import Foundation
import SwiftData

/// The only code that changes what's on a Canvas: nodes, belongs-to (`parent`), links, order.
/// Views call these instead of setting relationships themselves, so the rules live in one place:
///
/// - A node's parent is on the same Canvas and never one of its own descendants.
/// - Two nodes have at most one relates-to link, and none if one belongs to the other.
/// - Deleting a node moves its children up to its parent; `deleteBranch` takes them too.
/// - Every change bumps `Canvas.updatedAt`, which the views redraw from.
@MainActor
enum CanvasGraph {
    struct NewCanvas {
        let canvas: Canvas
        let root: CanvasNode
        let categories: [CanvasCategory]
    }

    // MARK: Canvases

    /// A new Canvas with its categories and one root Idea at the origin.
    @discardableResult
    static func makeCanvas(
        title: String,
        rootTitle: String = "",
        categories presets: [CanvasCategory.Preset] = CanvasCategory.defaults,
        in context: ModelContext
    ) -> NewCanvas {
        let canvas = Canvas(title: title)
        context.insert(canvas)

        let categories = presets.enumerated().map { index, preset in
            let category = CanvasCategory(name: preset.name, colorHex: preset.hex, order: index)
            context.insert(category)
            category.canvas = canvas
            return category
        }

        let root = CanvasNode(kind: .idea, x: 0, y: 0)
        context.insert(root)
        root.canvas = canvas
        root.isRoot = true
        root.title = rootTitle

        return NewCanvas(canvas: canvas, root: root, categories: categories)
    }

    /// Deletes a Canvas with its nodes, links and categories. References stay in the Library.
    static func deleteCanvas(_ canvas: Canvas, in context: ModelContext) {
        for link in canvas.links { context.delete(link) }
        for node in canvas.nodes { context.delete(node) }
        for category in canvas.categories { context.delete(category) }
        context.delete(canvas)
    }

    static func touch(_ canvas: Canvas?) {
        canvas?.updatedAt = .now
    }

    // MARK: Nodes

    /// Adds a node. With a parent it belongs to that node and takes its category unless one is given.
    @discardableResult
    static func addNode(
        _ kind: NodeKind,
        to canvas: Canvas,
        parent: CanvasNode? = nil,
        at position: CGPoint,
        title: String? = nil,
        body: String? = nil,
        reference: Reference? = nil,
        category: CanvasCategory? = nil,
        in context: ModelContext
    ) -> CanvasNode {
        let node = CanvasNode(kind: kind, x: position.x, y: position.y)
        context.insert(node)
        node.canvas = canvas
        node.title = title
        node.body = body
        node.reference = reference
        node.category = category ?? parent?.category
        node.sortIndex = nextSortIndex(under: parent, in: canvas)
        node.parent = parent
        touch(canvas)
        return node
    }

    /// Adds a node that belongs to `parent`, on the first free spot around it
    /// (`CanvasLayout.radialSlot`), fanning out on the side away from the parent's own parent.
    @discardableResult
    static func addChild(
        _ kind: NodeKind,
        under parent: CanvasNode,
        title: String? = nil,
        body: String? = nil,
        in context: ModelContext
    ) -> CanvasNode? {
        guard let canvas = parent.canvas else { return nil }
        let node = addNode(kind, to: canvas, parent: parent, at: parent.position, title: title, body: body, in: context)
        node.position = freeSpot(for: node, around: parent)
        return node
    }

    /// Where `node` fits around `parent` without covering anything else on the Canvas.
    static func freeSpot(for node: CanvasNode, around parent: CanvasNode) -> CGPoint {
        let occupied = (parent.canvas?.nodes ?? []).filter { $0 !== node }.map(rect(of:))
        let parentSize = CanvasLayout.size(of: parent)
        var away: CGFloat = 0
        if let grandparent = parent.parent, grandparent.position != parent.position {
            away = CGFloat(atan2(parent.y - grandparent.y, parent.x - grandparent.x))
        }
        return CanvasLayout.radialSlot(
            around: parent.position,
            radius: max(parentSize.width, parentSize.height) / 2,
            size: CanvasLayout.size(of: node),
            avoiding: occupied,
            startAngle: away
        )
    }

    /// The node's frame in canvas points.
    static func rect(of node: CanvasNode) -> CGRect {
        let size = CanvasLayout.size(of: node)
        return CGRect(x: node.x - size.width / 2, y: node.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Moves nodes by the same distance, in canvas points. One call, one undo step.
    static func move(_ nodes: [CanvasNode], by offset: CGSize) {
        guard offset != .zero, !nodes.isEmpty else { return }
        for node in nodes {
            node.x += Double(offset.width)
            node.y += Double(offset.height)
        }
        touch(nodes.first?.canvas)
    }

    /// Changes a node's own content (title, text, URL) and marks the Canvas changed.
    static func edit(_ node: CanvasNode, _ change: (CanvasNode) -> Void) {
        change(node)
        touch(node.canvas)
    }

    /// Names an Idea. A Canvas that has no title yet takes its root Idea's.
    static func rename(_ node: CanvasNode, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        node.title = trimmed.isEmpty ? nil : trimmed
        if node.isRoot, let canvas = node.canvas, canvas.title.isEmpty, !trimmed.isEmpty {
            canvas.title = trimmed
        }
        touch(node.canvas)
    }

    /// Gives nodes a category. Everything under an Idea that had the Idea's old category
    /// follows it; anything colored differently on purpose keeps its own.
    static func setCategory(_ nodes: [CanvasNode], to category: CanvasCategory?) {
        for node in nodes {
            let old = node.category
            if node.isIdea {
                for item in node.descendants where item.category === old {
                    item.category = category
                }
            }
            node.category = category
        }
        touch(nodes.first?.canvas)
    }

    /// Deletes what's selected. Root Ideas stay: delete the Canvas instead.
    /// - Parameter branch: also delete everything that belongs to each node (⌘⌫);
    ///   otherwise children move up to the deleted node's parent (⌫).
    /// - Returns: how many nodes were deleted.
    @discardableResult
    static func delete(_ nodes: [CanvasNode], branch: Bool, in context: ModelContext) -> Int {
        var targets = nodes.filter { !$0.isRoot }
        if branch {
            // A node inside another selected branch goes with that branch.
            targets = targets.filter { node in !targets.contains { node.isDescendant(of: $0) } }
        }
        var count = 0
        for node in targets {
            if branch {
                count += node.descendants.count + 1
                deleteBranch(node, in: context)
            } else {
                count += 1
                deleteNode(node, in: context)
            }
        }
        return count
    }

    /// Deletes one node and its links. Its children move up to its parent, or become loose.
    static func deleteNode(_ node: CanvasNode, in context: ModelContext) {
        let canvas = node.canvas
        let newParent = node.parent
        for child in node.sortedChildren {
            child.parent = newParent
            if newParent == nil { child.parentLabel = nil }
        }
        for link in node.outgoing + node.incoming {
            context.delete(link)
        }
        context.delete(node)
        touch(canvas)
    }

    /// Deletes a node together with everything that belongs to it, however deep.
    static func deleteBranch(_ node: CanvasNode, in context: ModelContext) {
        let canvas = node.canvas
        for item in node.descendants.reversed() + [node] {
            for link in item.outgoing + item.incoming {
                context.delete(link)
            }
            context.delete(item)
        }
        touch(canvas)
    }

    // MARK: Belongs to

    /// Makes `node` belong to `parent` (or to nothing). Refuses, and returns false, when the
    /// parent is the node itself, one of its descendants, or on another Canvas.
    /// A relates-to link between the two is dropped: belonging already connects them.
    @discardableResult
    static func setParent(
        _ node: CanvasNode,
        to parent: CanvasNode?,
        label: String? = nil,
        in context: ModelContext
    ) -> Bool {
        if let parent {
            guard parent !== node,
                  parent.canvas === node.canvas,
                  !parent.isDescendant(of: node)
            else { return false }
            if let existing = link(between: node, and: parent) {
                context.delete(existing)
            }
        }
        if node.parent !== parent {
            node.sortIndex = nextSortIndex(under: parent, in: node.canvas)
        }
        node.parent = parent
        node.parentLabel = parent == nil ? nil : label
        touch(node.canvas)
        return true
    }

    // MARK: Relates to

    /// Links two nodes with a "relates to" line. Returns nil, and changes nothing, if they're
    /// the same node, on different Canvases, already linked, or one belongs to the other.
    @discardableResult
    static func link(
        _ from: CanvasNode,
        to: CanvasNode,
        label: String? = nil,
        in context: ModelContext
    ) -> CanvasLink? {
        guard from !== to,
              let canvas = from.canvas,
              to.canvas === canvas,
              link(between: from, and: to) == nil,
              from.parent !== to,
              to.parent !== from
        else { return nil }

        let newLink = CanvasLink(label: label)
        context.insert(newLink)
        newLink.canvas = canvas
        newLink.from = from
        newLink.to = to
        touch(canvas)
        return newLink
    }

    static func unlink(_ link: CanvasLink, in context: ModelContext) {
        let canvas = link.canvas
        context.delete(link)
        touch(canvas)
    }

    /// The relates-to link between two nodes, in either direction.
    static func link(between a: CanvasNode, and b: CanvasNode) -> CanvasLink? {
        a.outgoing.first { $0.to === b } ?? a.incoming.first { $0.from === b }
    }

    // MARK: Changing a line

    /// Turns `child`'s belongs-to line into a relates-to link from its parent, keeping the label.
    @discardableResult
    static func convertToLink(child: CanvasNode, in context: ModelContext) -> CanvasLink? {
        guard let parent = child.parent else { return nil }
        let label = child.parentLabel
        setParent(child, to: nil, in: context)
        return link(parent, to: child, label: label, in: context)
    }

    /// Turns a relates-to link into belonging, keeping the label: `to` belongs to `from`, or the
    /// other way round when that would put a node under its own descendant. Returns false, and
    /// changes nothing, if neither way works.
    @discardableResult
    static func convertToParent(_ link: CanvasLink, in context: ModelContext) -> Bool {
        guard let from = link.from, let to = link.to else { return false }
        let label = link.label
        let child: CanvasNode
        let parent: CanvasNode
        if !from.isDescendant(of: to) {
            child = to
            parent = from
        } else if !to.isDescendant(of: from) {
            child = from
            parent = to
        } else {
            return false
        }
        // setParent drops the link between the two.
        return setParent(child, to: parent, label: label, in: context)
    }

    /// The label on a belongs-to line (stored on the child) or a relates-to link. Empty clears it.
    static func setLabel(_ label: String, child: CanvasNode? = nil, link: CanvasLink? = nil) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        if let child { child.parentLabel = value }
        if let link { link.label = value }
        touch(child?.canvas ?? link?.canvas)
    }

    // MARK: Order

    /// One past the last sibling, so a new node goes to the end.
    static func nextSortIndex(under parent: CanvasNode?, in canvas: Canvas?) -> Double {
        let siblings = parent?.children ?? canvas?.nodes.filter { $0.parent == nil } ?? []
        return (siblings.map(\.sortIndex).max() ?? -1) + 1
    }
}
