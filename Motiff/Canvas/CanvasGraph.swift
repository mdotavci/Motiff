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

    /// Puts References on a board, loose, in a grid that starts at `topLeft` (or beside what's
    /// already there): pictures on their own, prompts as cards. One that's already on the board
    /// isn't added again.
    @discardableResult
    static func addReferences(
        _ references: [Reference],
        to canvas: Canvas,
        topLeft: CGPoint? = nil,
        columns: Int = 4,
        in context: ModelContext
    ) -> [CanvasNode] {
        let existing = canvas.nodes.filter { !$0.isDeleted }
        var onBoard = Set(existing.compactMap { $0.reference?.id })
        var occupied = existing.map(rect(of:))
        let start = topLeft ?? CanvasLayout.besideContent(occupied)
        var made: [CanvasNode] = []
        for reference in references where !onBoard.contains(reference.id) {
            onBoard.insert(reference.id)
            let node = addNode(reference.hasMedia ? .reference : .prompt, to: canvas, at: start, reference: reference, in: context)
            // A picture on its own, as on a moodboard.
            node.isBare = reference.hasMedia
            made.append(node)
        }
        let centers = CanvasLayout.gridCenters(for: made.map(CanvasLayout.size(of:)), columns: columns, topLeft: start)
        for (node, center) in zip(made, centers) {
            node.position = CanvasLayout.openSpot(for: CanvasLayout.size(of: node), near: center, avoiding: occupied)
            occupied.append(rect(of: node))
        }
        return made
    }

    /// The cards that show `reference` on `canvas`.
    static func cards(of reference: Reference, on canvas: Canvas) -> [CanvasNode] {
        reference.canvasNodes.filter { $0.canvas === canvas && !$0.isDeleted }
    }

    /// A board made from one of the old Boards (image grids): the same name, its References as
    /// cards in a grid under the root Idea, newest first.
    @discardableResult
    static func makeCanvas(from board: Board, in context: ModelContext) -> Canvas {
        let new = makeCanvas(title: board.name, rootTitle: board.displayName, in: context)
        let columns = 4
        let width = CGFloat(columns) * (CanvasLayout.referenceWidth + CanvasLayout.slotGap)
        let rootBottom = CanvasLayout.ideaDiameters[0] / 2
        addReferences(
            board.sortedReferences,
            to: new.canvas,
            topLeft: CGPoint(x: -width / 2, y: rootBottom + 80),
            columns: columns,
            in: context
        )
        return new.canvas
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

    /// Ideas, notes, stickies, prompts and pictures can have things attached to them (an
    /// example image under a prompt, a screenshot under a note); text, shapes, links and
    /// arrows can't.
    static func canHold(_ node: CanvasNode) -> Bool {
        switch node.kind {
        case .idea, .note, .sticky, .prompt, .reference: true
        case .text, .shape, .link: false
        }
    }

    /// A sticky note at `position`, loose, in its color (yellow unless one is given).
    @discardableResult
    static func addSticky(to canvas: Canvas, at position: CGPoint, text: String = "", colorHex: String = "#F6D77A", in context: ModelContext) -> CanvasNode {
        let node = addNode(.sticky, to: canvas, at: position, body: text, in: context)
        node.colorHex = colorHex
        return node
    }

    /// A rectangle, circle, triangle, diamond or star at `position`, loose.
    @discardableResult
    static func addShape(_ shape: ShapeKind, to canvas: Canvas, at position: CGPoint, label: String = "", colorHex: String? = nil, in context: ModelContext) -> CanvasNode {
        let node = addNode(.shape, to: canvas, at: position, body: label, in: context)
        node.shape = shape
        node.colorHex = colorHex
        return node
    }

    /// A free arrow (or a line, without `arrow`) from `start` to `end`, loose.
    @discardableResult
    static func addLine(from start: CGPoint, to end: CGPoint, arrow: Bool = true, on canvas: Canvas, in context: ModelContext) -> CanvasNode {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let node = addNode(.shape, to: canvas, at: middle, in: context)
        node.shape = arrow ? .arrow : .line
        node.line = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        return node
    }

    /// A node made to fill `rect`. Ideas stay circles; Text scales its letters instead of
    /// getting a fixed box, so it still grows as it's typed into.
    static func resize(_ node: CanvasNode, to rect: CGRect) {
        guard !node.isLine, rect.width > 0, rect.height > 0 else { return }
        let old = CanvasLayout.size(of: node)
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        switch node.kind {
        case .text:
            let scale = rect.height / max(old.height, 1)
            node.fontSize = min(max((node.effectiveFontSize * Double(scale)).rounded(), 6), 400)
            node.width = nil
            node.height = nil
        case .idea:
            let diameter = Double(max(rect.width, rect.height))
            node.width = diameter
            node.height = diameter
        default:
            node.width = Double(rect.width)
            node.height = Double(rect.height)
        }
        touch(node.canvas)
    }

    /// Back to the kind's own size.
    static func resetSize(_ node: CanvasNode) {
        node.width = nil
        node.height = nil
        if node.kind == .text { node.fontSize = nil }
        touch(node.canvas)
    }

    /// Moves an arrow's or line's ends.
    static func setLine(_ node: CanvasNode, from start: CGPoint, to end: CGPoint) {
        guard node.isLine else { return }
        node.position = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        node.line = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        touch(node.canvas)
    }

    /// The letters' size of every node with words in `nodes`, kept between 6 and 400.
    static func setFontSize(_ size: Double, of nodes: [CanvasNode]) {
        let size = min(max(size, 6), 400)
        for node in nodes where node.hasWords {
            node.fontSize = size
        }
        touch(nodes.first?.canvas)
    }

    /// Arrows' and lines' thickness, or shapes' border (0 for none).
    static func setStrokeWidth(_ width: Double, of nodes: [CanvasNode]) {
        for node in nodes where node.kind == .shape {
            node.strokeWidth = max(width, 0)
        }
        touch(nodes.first?.canvas)
    }

    static func setDashed(_ dashed: Bool, of nodes: [CanvasNode]) {
        for node in nodes where node.isLine {
            node.isDashed = dashed
        }
        touch(nodes.first?.canvas)
    }

    /// A link's look: how thick, dashed or solid, and its heads.
    static func style(_ link: CanvasLink, width: Double? = nil, dashed: Bool? = nil, startArrow: Bool? = nil, endArrow: Bool? = nil) {
        if let width { link.lineWidth = width }
        if let dashed { link.isDashed = dashed }
        if let startArrow { link.hasStartArrow = startArrow }
        if let endArrow { link.hasArrow = endArrow }
        touch(link.canvas)
    }

    /// A picture on its own, or in its card.
    static func setBare(_ bare: Bool, of nodes: [CanvasNode]) {
        for node in nodes where node.kind == .reference {
            node.isBare = bare
            // Its old size was the card's.
            node.width = nil
            node.height = nil
        }
        touch(nodes.first?.canvas)
    }

    /// A free arrow's or line's arrowheads. With none at the end it's a line, otherwise an arrow.
    static func setArrowheads(of node: CanvasNode, start: Bool, end: Bool) {
        guard node.isLine else { return }
        node.shape = end ? .arrow : .line
        node.hasStartArrow = start
        touch(node.canvas)
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

    // MARK: Categories

    /// A new category at the end of the legend, in the first swatch no other category uses.
    @discardableResult
    static func addCategory(to canvas: Canvas, name: String = "New category", in context: ModelContext) -> CanvasCategory {
        let used = Set(canvas.categories.map(\.colorHex))
        let swatch = CanvasCategory.swatches.first { !used.contains($0.hex) } ?? CanvasCategory.swatches[canvas.categories.count % CanvasCategory.swatches.count]
        let category = CanvasCategory(name: name, colorHex: swatch.hex, order: (canvas.categories.map(\.order).max() ?? -1) + 1)
        context.insert(category)
        category.canvas = canvas
        touch(canvas)
        return category
    }

    /// Deletes a category. Its nodes keep everything else and lose only the color.
    static func deleteCategory(_ category: CanvasCategory, in context: ModelContext) {
        let canvas = category.canvas
        for node in category.nodes { node.category = nil }
        context.delete(category)
        if let canvas {
            renumber(canvas.sortedCategories.filter { $0 !== category })
        }
        touch(canvas)
    }

    /// Moves a category one place up (-1) or down (+1) in the legend.
    static func moveCategory(_ category: CanvasCategory, by step: Int) {
        guard let canvas = category.canvas else { return }
        var ordered = canvas.sortedCategories
        guard let index = ordered.firstIndex(where: { $0 === category }) else { return }
        let target = index + step
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        renumber(ordered)
        touch(canvas)
    }

    static func renameCategory(_ category: CanvasCategory, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        category.name = trimmed
        touch(category.canvas)
    }

    /// Any color but one too close to focus red. Returns false when it's refused.
    @discardableResult
    static func setColor(_ category: CanvasCategory, to hex: String) -> Bool {
        guard let hex = CanvasCategory.normalized(hex), !CanvasCategory.isFocusRed(hex) else { return false }
        category.colorHex = hex
        touch(category.canvas)
        return true
    }

    // MARK: Look

    /// The fill of Ideas and Notes, the strip of cards, the words of Text. nil goes back to the
    /// category's color. Refuses colors too close to focus red.
    @discardableResult
    static func setColor(_ hex: String?, of nodes: [CanvasNode]) -> Bool {
        guard let value = checked(hex) else { return false }
        for node in nodes {
            if node.kind == .text { node.textColorHex = value } else { node.colorHex = value }
        }
        touch(nodes.first?.canvas)
        return true
    }

    /// The words of Ideas, Notes and Text. nil picks black or white for the fill.
    @discardableResult
    static func setTextColor(_ hex: String?, of nodes: [CanvasNode]) -> Bool {
        guard let value = checked(hex) else { return false }
        for node in nodes { node.textColorHex = value }
        touch(nodes.first?.canvas)
        return true
    }

    /// A line's color: a link's own, or the belongs-to line stored on its child.
    @discardableResult
    static func setLineColor(_ hex: String?, child: CanvasNode?, link: CanvasLink?) -> Bool {
        guard let value = checked(hex) else { return false }
        child?.lineColorHex = value
        link?.colorHex = value
        touch(child?.canvas ?? link?.canvas)
        return true
    }

    static func setArrow(_ on: Bool, child: CanvasNode?, link: CanvasLink?) {
        child?.lineHasArrow = on
        link?.hasArrow = on
        touch(child?.canvas ?? link?.canvas)
    }

    /// `.some(nil)` to clear, `.some(hex)` when the color is usable, nil when it's refused.
    private static func checked(_ hex: String?) -> String?? {
        guard let hex else { return .some(nil) }
        guard let normalized = CanvasCategory.normalized(hex), !CanvasCategory.isFocusRed(normalized) else { return nil }
        return .some(normalized)
    }

    /// Moves Canvases made with the first palette onto the pastel one. Custom colors stay.
    static func migrateToPastelPalette(_ categories: [CanvasCategory]) {
        for category in categories {
            if let pastel = CanvasCategory.legacyColors[category.colorHex.uppercased()] {
                category.colorHex = pastel
            }
        }
    }

    private static func renumber(_ categories: [CanvasCategory]) {
        for (index, category) in categories.enumerated() where category.order != index {
            category.order = index
        }
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

    /// Moves a node one place up (-1) or down (+1) among its siblings. False at either end.
    @discardableResult
    static func moveAmongSiblings(_ node: CanvasNode, by step: Int) -> Bool {
        var level = siblings(of: node)
        guard let index = level.firstIndex(where: { $0 === node }),
              level.indices.contains(index + step)
        else { return false }
        level.swapAt(index, index + step)
        renumber(level)
        touch(node.canvas)
        return true
    }

    /// Tab in the Outline: the node goes under the sibling above it, as its last child.
    @discardableResult
    static func indent(_ node: CanvasNode, in context: ModelContext) -> Bool {
        let level = siblings(of: node)
        guard let index = level.firstIndex(where: { $0 === node }), index > 0, !node.isRoot else { return false }
        return setParent(node, to: level[index - 1], in: context)
    }

    /// ⇧Tab in the Outline: the node moves up a level, right after the node it was under.
    /// Out from under a root it becomes loose.
    @discardableResult
    static func outdent(_ node: CanvasNode, in context: ModelContext) -> Bool {
        guard let parent = node.parent, setParent(node, to: parent.parent, in: context) else { return false }
        var level = siblings(of: node).filter { $0 !== node }
        let after = level.firstIndex(where: { $0 === parent }).map { $0 + 1 } ?? level.count
        level.insert(node, at: after)
        renumber(level)
        return true
    }

    private static func renumber(_ nodes: [CanvasNode]) {
        for (index, node) in nodes.enumerated() where node.sortIndex != Double(index) {
            node.sortIndex = Double(index)
        }
    }

    /// The node and the others at its level, in order: what ← and → step through in the detail.
    static func siblings(of node: CanvasNode) -> [CanvasNode] {
        if let parent = node.parent { return parent.sortedChildren }
        guard let canvas = node.canvas else { return [node] }
        return node.isRoot ? canvas.roots : canvas.unattachedNodes
    }

    /// One past the last sibling, so a new node goes to the end.
    static func nextSortIndex(under parent: CanvasNode?, in canvas: Canvas?) -> Double {
        let siblings = parent?.children ?? canvas?.nodes.filter { $0.parent == nil } ?? []
        return (siblings.map(\.sortIndex).max() ?? -1) + 1
    }
}
