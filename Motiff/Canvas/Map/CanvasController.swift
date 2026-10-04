import CoreGraphics
import Foundation
import Observation
import SwiftData

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
    /// The pointer over the map, in view points; nil when it's elsewhere.
    var pointer: CGPoint?

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

    // MARK: Selection

    /// Selected nodes in sibling order.
    var selectedNodes: [CanvasNode] {
        selection.compactMap { self.node($0) }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The one selected node, if exactly one is.
    var selectedNode: CanvasNode? {
        selection.count == 1 ? selection.first.flatMap(node) : nil
    }

    /// Click selects; ⇧-click adds or removes.
    func tap(_ id: UUID, extending: Bool) {
        guard editingID != id else { return }
        endEditing()
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func clearSelection() {
        endEditing()
        selection = []
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
    /// References and Prompts are edited in the inspector, which this opens.
    func beginEditing(_ id: UUID? = nil) {
        guard let id = id ?? selectedNode?.id, let node = self.node(id), editingID != id else { return }
        endEditing()
        switch node.kind {
        case .idea, .link:
            editDraft = node.title ?? ""
        case .note:
            editDraft = node.body ?? ""
        case .reference, .prompt:
            selection = [id]
            showsInspector = true
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

    #if DEBUG
    /// `-MotiffSelect <title>` selects a node; `-MotiffInspector YES` opens the inspector.
    private func applyLaunchSelection() {
        guard let title = DebugLaunchRoute.selectTitle,
              let node = canvas.nodes.first(where: { $0.displayTitle == title })
        else { return }
        selection = [node.id]
        editingID = nil
        showsInspector = DebugLaunchRoute.showsInspector
    }
    #endif
}
