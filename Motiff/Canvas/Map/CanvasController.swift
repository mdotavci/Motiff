import CoreGraphics
import Foundation
import Observation
import SwiftData
#if os(macOS)
import AppKit
#endif

/// State for one open Canvas: what the Map shows (`snapshot`), where it's looking (`camera`),
/// what's selected, being edited or dragged. One per Canvas view; the Canvas itself stays the
/// source of truth, and every change to it goes through `CanvasGraph`.
@MainActor
@Observable
final class CanvasController {
    let canvas: Canvas

    private(set) var camera: CanvasCamera
    private(set) var viewSize: CGSize = .zero
    private(set) var snapshot: CanvasSnapshot = .empty
    /// The pointer over the map, in view points; nil when it's elsewhere. Set with `setPointer`.
    private(set) var pointer: CGPoint?
    /// The node under the pointer (its handle shows) and the line under it (right-click acts on it).
    private(set) var hoveredNodeID: UUID?
    private(set) var hoveredEdgeID: String?

    private(set) var selection: Set<UUID> = []
    /// The node whose text is being typed into on the Map, and the text so far.
    private(set) var editingID: UUID?
    var editDraft = ""
    /// Nodes being dragged and how far, in canvas points. Written to the Canvas on drop.
    private(set) var drag: Drag?
    var showsInspector = false

    struct Drag: Equatable {
        var ids: Set<UUID>
        var offset: CGSize
    }

    /// A line being drawn from a node's handle: where the pointer is (canvas points), what's
    /// under it, and whether it makes a relates-to link (⌥) or belonging.
    private(set) var connect: Connect?

    struct Connect: Equatable {
        var sourceID: UUID
        var point: CGPoint
        var targetID: UUID?
        var isLink: Bool
    }

    /// What's open full size over the Map, last on top: nodes of this Canvas, or a Reference
    /// reached from one (a Remix) that isn't on it. Esc goes back one; empty shows the Map.
    private(set) var detailPath: [DetailItem] = []

    enum DetailItem: Equatable {
        case node(UUID)
        case reference(Reference)

        static func == (lhs: DetailItem, rhs: DetailItem) -> Bool {
            switch (lhs, rhs) {
            case let (.node(a), .node(b)): a == b
            case let (.reference(a), .reference(b)): a === b
            default: false
            }
        }
    }

    /// L: click two nodes to link them. `linkSourceID` is the first one clicked.
    private(set) var linkMode = false
    private(set) var linkSourceID: UUID?

    /// A Note just made with Tab: if it's left empty, it isn't kept.
    @ObservationIgnored private var freshID: UUID?

    @ObservationIgnored private var nodesByID: [UUID: CanvasNode] = [:]
    @ObservationIgnored private var needsFit: Bool
    /// True while the camera is still the automatic fit, so a resize (the window settling,
    /// the inspector opening) fits again. Any pan or zoom by the user ends it.
    @ObservationIgnored private var isAutoFitted = false
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

        // A brand-new Canvas opens with its root Idea ready to be named.
        if canvas.title.isEmpty, canvas.nodes.count == 1, let root = canvas.roots.first, (root.title ?? "").isEmpty {
            selection = [root.id]
            editingID = root.id
        }
        #if DEBUG
        applyLaunchSelection()
        #endif
    }

    private var context: ModelContext? { canvas.modelContext }

    /// Rebuilds the snapshot from the Canvas. Call when it changes (`updatedAt`).
    func reload() {
        snapshot = CanvasSnapshot(canvas: canvas)
        nodesByID = Dictionary(
            canvas.nodes.filter { !$0.isDeleted }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let live = selection.filter { nodesByID[$0] != nil }
        if live != selection { selection = live }
        if let editingID, nodesByID[editingID] == nil { self.editingID = nil }
        let livePath = detailPath.filter { item in
            guard case let .node(id) = item else { return true }
            return nodesByID[id] != nil
        }
        if livePath != detailPath { detailPath = livePath }
        fitIfNeeded()
    }

    /// The node for an id, unless it has been deleted (or un-done) since the last reload.
    func node(_ id: UUID) -> CanvasNode? {
        guard let node = nodesByID[id], !node.isDeleted, node.modelContext != nil else { return nil }
        return node
    }

    /// The snapshot as drawn: with the nodes being dragged at their drag position.
    var displayedSnapshot: CanvasSnapshot {
        guard let drag else { return snapshot }
        return snapshot.moving(drag.ids, by: drag.offset)
    }

    /// Nodes on screen or near it, in `shown`. Only these get views.
    func visibleNodes(in shown: CanvasSnapshot) -> [CanvasSnapshot.Node] {
        guard viewSize.width > 0, viewSize.height > 0 else { return [] }
        let margin = Self.cullMargin / camera.zoom
        return shown.nodes(intersecting: camera.visibleRect(in: viewSize).insetBy(dx: -margin, dy: -margin))
    }

    private func save() {
        try? context?.save()
    }

    func setViewSize(_ size: CGSize) {
        viewSize = size
        if isAutoFitted { needsFit = true }
        fitIfNeeded()
    }

    // MARK: Moving the camera

    func pan(by screenDelta: CGSize) {
        isAutoFitted = false
        move(to: camera.panned(by: screenDelta))
    }

    /// Zooms around `anchor` (a view point), or around the middle of the view.
    func zoom(by factor: CGFloat, at anchor: CGPoint? = nil) {
        let point = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        isAutoFitted = false
        move(to: camera.zoomed(by: factor, anchor: point, in: viewSize))
    }

    func zoomIn() { zoom(by: Self.zoomStep) }
    func zoomOut() { zoom(by: 1 / Self.zoomStep) }

    func fitToContent() {
        guard viewSize.width > 0, !snapshot.nodes.isEmpty else { return }
        move(to: .fitting(snapshot.bounds, in: viewSize))
    }

    /// Smaller than this, the view is still being laid out; fitting to it would zoom all the way out.
    private static let minimumFitSize: CGFloat = 200

    private func fitIfNeeded() {
        guard needsFit, viewSize.width >= Self.minimumFitSize, viewSize.height >= Self.minimumFitSize,
              !snapshot.nodes.isEmpty
        else { return }
        needsFit = false
        fitToContent()
        isAutoFitted = true
    }

    /// Pans just enough to bring a node fully into view.
    func reveal(_ id: UUID) {
        guard viewSize.width > 0, let rect = snapshot.node(id)?.rect else { return }
        let inset = 40 / camera.zoom
        let visible = camera.visibleRect(in: viewSize).insetBy(dx: inset, dy: inset)
        guard !visible.contains(rect) else { return }
        isAutoFitted = false
        var center = camera.center
        if rect.minX < visible.minX {
            center.x -= visible.minX - rect.minX
        } else if rect.maxX > visible.maxX {
            center.x += rect.maxX - visible.maxX
        }
        if rect.minY < visible.minY {
            center.y -= visible.minY - rect.minY
        } else if rect.maxY > visible.maxY {
            center.y += rect.maxY - visible.maxY
        }
        move(to: CanvasCamera(center: center, zoom: camera.zoom))
    }

    private func move(to newCamera: CanvasCamera) {
        guard newCamera != camera else { return }
        camera = newCamera
        scheduleViewportSave()
    }

    /// Writes the viewport back half a second after the camera stops, so reopening the
    /// Canvas shows the same place without a write per frame. Looking around isn't an edit,
    /// so it stays out of Undo.
    private func scheduleViewportSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !self.canvas.isDeleted else { return }
            let camera = self.camera
            let undo = self.context?.undoManager
            self.save()
            undo?.disableUndoRegistration()
            self.canvas.viewport = CanvasViewport(centerX: camera.center.x, centerY: camera.center.y, zoom: camera.zoom)
            self.save()
            undo?.enableUndoRegistration()
        }
    }

    /// Runs an edit made outside the Map (the inspector), then saves and redraws.
    func update(_ change: () -> Void) {
        change()
        save()
        reload()
    }

    // MARK: Hover

    /// How close (in view points) the pointer must be to a line to pick it.
    static let edgeTolerance: CGFloat = 6
    /// How far past a node's outline (view points) it stays hovered, so its handle can be reached.
    static let hoverReach: CGFloat = 16

    func setPointer(_ point: CGPoint?) {
        // Under a detail, the Map isn't being pointed at.
        pointer = isShowingDetail ? nil : point
        guard let point = pointer, viewSize.width > 0 else {
            hoveredNodeID = nil
            hoveredEdgeID = nil
            return
        }
        let canvasPoint = camera.canvasPoint(point, in: viewSize)
        let reach = Self.hoverReach / camera.zoom
        var nodeID = snapshot.node(at: canvasPoint)?.id
        if nodeID == nil, let current = hoveredNodeID.flatMap({ snapshot.node($0) }),
           current.rect.insetBy(dx: -reach, dy: -reach).contains(canvasPoint) {
            nodeID = current.id
        }
        let edgeID = nodeID == nil ? snapshot.edge(near: canvasPoint, tolerance: Self.edgeTolerance / camera.zoom)?.id : nil
        if nodeID != hoveredNodeID { hoveredNodeID = nodeID }
        if edgeID != hoveredEdgeID { hoveredEdgeID = edgeID }
    }

    var hoveredEdge: CanvasSnapshot.Edge? {
        hoveredEdgeID.flatMap { snapshot.edge($0) }
    }

    /// While something is selected: it and everything one line away. Nil means nothing is dimmed.
    var highlighted: Set<UUID>? {
        selection.isEmpty ? nil : snapshot.neighbors(of: selection)
    }

    // MARK: Selection

    /// Selected nodes in sibling order.
    var selectedNodes: [CanvasNode] {
        selection.compactMap { self.node($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The one selected node, if exactly one is.
    var selectedNode: CanvasNode? {
        selection.count == 1 ? selection.first.flatMap(node) : nil
    }

    /// Click selects; ⇧-click adds or removes. In link mode, the second click links.
    func tap(_ id: UUID, extending: Bool) {
        guard editingID != id else { return }
        endEditing()
        if linkMode {
            if let sourceID = linkSourceID, sourceID != id {
                makeLink(from: sourceID, to: id)
                linkSourceID = nil
            } else {
                linkSourceID = id
            }
            selection = [id]
            return
        }
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func clearSelection() {
        endEditing()
        linkSourceID = nil
        selection = []
    }

    /// Selects a node and pans to it, e.g. from the inspector's link lists.
    func focus(on id: UUID) {
        endEditing()
        selection = [id]
        reveal(id)
    }

    func toggleInspector() {
        showsInspector.toggle()
    }

    // MARK: Adding

    /// Tab: a Note on the selected Idea (or the selected card's Idea, or the root), typed into.
    func addNote() {
        add(.note)
    }

    /// ⌘Return: a sub-idea of the selected Idea (or the selected card's Idea, or the root).
    func addSubIdea() {
        add(.idea)
    }

    private func add(_ kind: NodeKind) {
        endEditing()
        guard let context, let parent = anchorIdea,
              let node = CanvasGraph.addChild(kind, under: parent, body: kind == .note ? "" : nil, in: context)
        else { return }
        save()
        reload()
        selection = [node.id]
        if kind == .note { freshID = node.id }
        beginEditing(node.id)
        reveal(node.id)
    }

    /// The Idea new things attach to.
    private var anchorIdea: CanvasNode? {
        if let selected = selectedNode {
            if selected.isIdea { return selected }
            if let idea = selected.ancestors.first(where: \.isIdea) { return idea }
        }
        return canvas.roots.first
    }

    // MARK: Editing in place

    /// Return or double-click: type into an Idea's title, a Note's text or a Link's title.
    /// References and Prompts have no text of their own here: they open full size.
    func beginEditing(_ id: UUID? = nil) {
        guard let id = id ?? selectedNode?.id, let node = self.node(id), editingID != id else { return }
        endEditing()
        switch node.kind {
        case .idea, .link:
            editDraft = node.title ?? ""
        case .note:
            editDraft = node.body ?? ""
        case .reference, .prompt:
            openDetail(id)
            return
        }
        selection = [id]
        editingID = id
    }

    /// Ends editing `id`, if it's still the node being edited. Text fields call this, so a
    /// field that loses focus after another node took over can't end the new edit.
    func finishEditing(_ id: UUID, commit: Bool = true) {
        guard editingID == id else { return }
        endEditing(commit: commit)
    }

    /// Return or a click elsewhere keeps the text; Esc (`commit: false`) puts it back.
    func endEditing(commit: Bool = true) {
        guard let id = editingID else { return }
        editingID = nil
        let fresh = freshID == id
        freshID = nil
        guard let context, let node = self.node(id) else { return }
        let text = editDraft
        if commit {
            switch node.kind {
            case .idea:
                if text != (node.title ?? "") { CanvasGraph.rename(node, to: text) }
            case .link:
                if text != (node.title ?? "") { CanvasGraph.edit(node) { $0.title = text.isEmpty ? nil : text } }
            case .note:
                if text != (node.body ?? "") { CanvasGraph.edit(node) { $0.body = text } }
            case .reference, .prompt:
                break
            }
        }
        if fresh, node.kind == .note, (node.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            CanvasGraph.delete([node], branch: false, in: context)
        }
        save()
        reload()
    }

    // MARK: Deleting

    /// ⌫ deletes the selection (an Idea's children move up to its parent);
    /// ⌘⌫ (`branch`) also deletes everything that belongs to it. The root stays.
    func deleteSelection(branch: Bool) {
        endEditing()
        guard let context else { return }
        let nodes = selectedNodes
        guard !nodes.isEmpty, CanvasGraph.delete(nodes, branch: branch, in: context) > 0 else { return }
        save()
        reload()
    }

    // MARK: Dragging

    /// Moves the dragged node, or the whole selection if it's part of it. An Idea brings
    /// everything that belongs to it unless `alone` (⌥-drag).
    func dragChanged(_ id: UUID, translation: CGSize, alone: Bool) {
        if drag == nil {
            endEditing()
            if !selection.contains(id) { selection = [id] }
            var ids = selection
            if !alone {
                for idea in selection.compactMap({ self.node($0) }) where idea.isIdea {
                    ids.formUnion(idea.descendants.map(\.id))
                }
            }
            drag = Drag(ids: ids, offset: .zero)
        }
        drag?.offset = CGSize(width: translation.width / camera.zoom, height: translation.height / camera.zoom)
    }

    /// Writes the drag to the Canvas: one change, one Undo step.
    func dragEnded() {
        guard let drag else { return }
        if drag.offset != .zero {
            CanvasGraph.move(drag.ids.compactMap { self.node($0) }, by: drag.offset)
            save()
            reload()
        }
        self.drag = nil
    }

    // MARK: Connecting

    /// Dragging a node's handle. Over another node, that node is the target.
    func connectChanged(from sourceID: UUID, at viewPoint: CGPoint, isLink: Bool) {
        if connect == nil { endEditing() }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        let target = snapshot.node(at: point).map(\.id)
        connect = Connect(sourceID: sourceID, point: point, targetID: target == sourceID ? nil : target, isLink: isLink)
    }

    /// Drops the line: the dragged node belongs to the target, or with ⌥ they're linked.
    /// Anything the rules refuse (a cycle, a duplicate) beeps and changes nothing.
    func connectEnded() {
        guard let connect else { return }
        self.connect = nil
        guard let targetID = connect.targetID else { return }
        if connect.isLink {
            makeLink(from: connect.sourceID, to: targetID)
        } else if let context, let source = node(connect.sourceID), let target = node(targetID) {
            guard source.parent !== target else { return }
            if CanvasGraph.setParent(source, to: target, in: context) {
                save()
                reload()
            } else {
                Self.refuse()
            }
        }
    }

    func toggleLinkMode() {
        endEditing()
        linkMode.toggle()
        linkSourceID = nil
    }

    private func makeLink(from sourceID: UUID, to targetID: UUID) {
        guard let context, let source = node(sourceID), let target = node(targetID) else { return }
        if CanvasGraph.link(source, to: target, in: context) != nil {
            save()
            reload()
        } else {
            Self.refuse()
        }
    }

    // MARK: Lines

    /// The child of a belongs-to line, or the link of a relates-to one.
    private func parts(of edge: CanvasSnapshot.Edge) -> (child: CanvasNode?, link: CanvasLink?) {
        switch edge.type {
        case .belongsTo:
            return (node(edge.to), nil)
        case .relatesTo:
            guard let from = node(edge.from), let to = node(edge.to) else { return (nil, nil) }
            return (nil, CanvasGraph.link(between: from, and: to))
        }
    }

    func setLabel(_ label: String, on edge: CanvasSnapshot.Edge) {
        let (child, link) = parts(of: edge)
        guard child != nil || link != nil else { return }
        update { CanvasGraph.setLabel(label, child: child, link: link) }
    }

    /// Belongs to ⇄ relates to.
    func convert(_ edge: CanvasSnapshot.Edge) {
        guard let context else { return }
        let (child, link) = parts(of: edge)
        var done = false
        if let child {
            done = CanvasGraph.convertToLink(child: child, in: context) != nil
        } else if let link {
            done = CanvasGraph.convertToParent(link, in: context)
        }
        if done {
            save()
            reload()
        } else {
            Self.refuse()
        }
    }

    /// Deletes a link, or detaches a node from what it belongs to (it stays on the Canvas).
    func deleteEdge(_ edge: CanvasSnapshot.Edge) {
        guard let context else { return }
        let (child, link) = parts(of: edge)
        if let child {
            CanvasGraph.setParent(child, to: nil, in: context)
        } else if let link {
            CanvasGraph.unlink(link, in: context)
        } else {
            return
        }
        save()
        reload()
    }

    func unlink(_ link: CanvasLink) {
        guard let context else { return }
        update { CanvasGraph.unlink(link, in: context) }
    }

    func detach(_ node: CanvasNode) {
        guard let context else { return }
        update { CanvasGraph.setParent(node, to: nil, in: context) }
    }

    /// Something the Canvas's rules don't allow.
    private static func refuse() {
        #if os(macOS)
        NSSound.beep()
        #endif
    }

    // MARK: Detail

    var detailItem: DetailItem? { detailPath.last }
    var isShowingDetail: Bool { !detailPath.isEmpty }

    /// Space or double-click: the node full size. From inside a detail, it goes on top.
    func openDetail(_ id: UUID? = nil) {
        guard let id = id ?? selectedNode?.id, node(id) != nil else { return }
        endEditing()
        if linkMode { toggleLinkMode() }
        detailPath.append(.node(id))
        selection = [id]
    }

    /// A Reference from inside a detail: its card on this Canvas if it has one.
    func openDetail(reference: Reference) {
        if let card = reference.canvasNodes.first(where: { $0.canvas === canvas && !$0.isDeleted }) {
            openDetail(card.id)
        } else {
            detailPath.append(.reference(reference))
        }
    }

    /// Esc: back one; out of the last one, the Map is where it was, with that node selected.
    func closeDetail() {
        guard let closing = detailPath.popLast() else { return }
        if detailPath.isEmpty, case let .node(id) = closing {
            selection = [id]
            reveal(id)
        }
    }

    /// ← / →: the previous or next node at the same level, in sibling order.
    func stepDetail(by step: Int) {
        guard let position = detailPosition else { return }
        let next = position.index + step
        guard position.siblings.indices.contains(next) else { return }
        detailPath[detailPath.count - 1] = .node(position.siblings[next].id)
        selection = [position.siblings[next].id]
    }

    /// Where the open node sits among its siblings.
    var detailPosition: (index: Int, siblings: [CanvasNode])? {
        guard case let .node(id) = detailItem, let node = node(id) else { return nil }
        let siblings = CanvasGraph.siblings(of: node)
        guard let index = siblings.firstIndex(where: { $0 === node }) else { return nil }
        return (index, siblings)
    }

    /// The prompt of the open node, or of the one selected node.
    var promptToCopy: String? {
        switch detailItem {
        case .reference(let reference):
            return reference.copyablePrompt
        case .node(let id):
            return node(id)?.reference?.copyablePrompt
        case nil:
            return selectedNode?.reference?.copyablePrompt
        }
    }

    /// ⌘⇧C.
    func copyPrompt() {
        if let prompt = promptToCopy { Pasteboard.copy(prompt) }
    }

    /// Where a node is on screen, for the detail to grow out of and shrink back into.
    func screenRect(of id: UUID) -> CGRect? {
        guard let rect = snapshot.node(id)?.rect, viewSize.width > 0 else { return nil }
        let origin = camera.screenPoint(rect.origin, in: viewSize)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * camera.zoom, height: rect.height * camera.zoom)
    }

    #if DEBUG
    /// `-MotiffSelect <title>` selects a node; `-MotiffInspector YES` opens the inspector.
    private func applyLaunchSelection() {
        guard let title = DebugLaunchRoute.selectTitle,
              let node = canvas.nodes.first(where: { $0.displayTitle == title })
                ?? canvas.nodes.first(where: { $0.displayTitle.hasPrefix(title) })
        else { return }
        selection = [node.id]
        editingID = nil
        showsInspector = DebugLaunchRoute.showsInspector
        if DebugLaunchRoute.showsDetail { detailPath = [.node(node.id)] }
    }
    #endif
}
