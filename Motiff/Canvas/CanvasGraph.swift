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

    // MARK: Order

    /// One past the last sibling, so a new node goes to the end.
    static func nextSortIndex(under parent: CanvasNode?, in canvas: Canvas?) -> Double {
        let siblings = parent?.children ?? canvas?.nodes.filter { $0.parent == nil } ?? []
        return (siblings.map(\.sortIndex).max() ?? -1) + 1
    }
}
