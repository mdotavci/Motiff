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

    /// A free arrow being drawn with the Arrow tool on empty board, in canvas points.
    private(set) var arrowDraft: ArrowDraft?

    struct ArrowDraft: Equatable {
        var start: CGPoint
        var end: CGPoint
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

    /// ⌘F: the find bar is open, what's typed in it, the matching nodes in Outline order, and
    /// which one ⌘G last went to.
    private(set) var isSearching = false
    private(set) var searchText = ""
    private(set) var searchResults: [UUID] = []
    private(set) var searchIndex: Int?

    /// ⌥⌘M. Remembered across launches.
    private(set) var showsMinimap = UserDefaults.standard.object(forKey: "canvas.minimap") as? Bool ?? true
    static let minimapKey = "canvas.minimap"

    /// Map, Outline or Graph (⌘1 ⌘2 ⌘3).
    private(set) var viewMode: CanvasViewMode = .map
    /// Outline rows whose children are folded away.
    private(set) var collapsed: Set<UUID> = []
    /// A node to bring into view once the Map is showing (from the Graph's Return).
    @ObservationIgnored private var pendingRevealID: UUID?

    /// Legend filters: only nodes in these categories, and with these prompt purposes, stay at
    /// full strength. Empty means no filter. Filters dim; they never hide.
    private(set) var categoryFilter: Set<UUID> = []
    private(set) var purposeFilter: Set<PromptPurpose> = []

    /// The node under something being dragged in from outside; dropping attaches to its Idea.
    private(set) var dropTargetID: UUID?

    /// The Arrow tool (A, or L): click two nodes to link them. `linkSourceID` is the first one clicked.
    private(set) var linkMode = false
    private(set) var linkSourceID: UUID?

    /// What a click on the board does: select (V), pan (H), or put something there: a sticky,
    /// note, text, prompt, image, shape or Idea (S N T P I R O). The Arrow (A) links what you
    /// click or drag between, or draws a free arrow. Adding tools go back to Select once used.
    private(set) var tool: CanvasTool = .select
    /// The shape the Shape tool (R) places; the bar remembers the last one picked.
    private(set) var shapeTool: ShapeKind = .rectangle
    /// ⌥⌘L: the Library panel beside the Map, to drag References in from.
    var showsLibrary = false

    /// A line clicked on the Map: ⌫ deletes it, C colors it, A turns its arrow on or off.
    /// A node selection and a line selection never coexist.
    private(set) var selectedEdgeID: String?
    /// C, or the selection bar's color dot: the color popover is open.
    var showsColorPicker = false

    /// A Note just made with Tab: if it's left empty, it isn't kept.
    @ObservationIgnored private var freshID: UUID?

    /// Observed, so views that look a node up redraw once it's loaded. It changes with `snapshot`.
    private var nodesByID: [UUID: CanvasNode] = [:]
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

    init(canvas: Canvas, viewMode: CanvasViewMode = .map) {
        self.canvas = canvas
        let viewport = canvas.viewport
        camera = CanvasCamera(center: CGPoint(x: viewport.centerX, y: viewport.centerY), zoom: viewport.zoom)
        // A Canvas that has never been looked at opens fitted to its content.
        needsFit = viewport == .initial
        self.viewMode = viewMode

        // A brand-new Canvas opens with its root Idea ready to be named.
        if canvas.title.isEmpty, canvas.nodes.count == 1, let root = canvas.roots.first, (root.title ?? "").isEmpty {
            selection = [root.id]
            editingID = root.id
        }
        #if DEBUG
        applyLaunchSelection()
        applyLaunchFilter()
        showsLibrary = DebugLaunchRoute.showsDrawer
        if let mode = DebugLaunchRoute.viewName.flatMap(CanvasViewMode.init(rawValue:)) { self.viewMode = mode }
        if let text = DebugLaunchRoute.findText {
            isSearching = true
            searchText = text
        }
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
        if let selectedEdgeID, snapshot.edge(selectedEdgeID) == nil { self.selectedEdgeID = nil }
        if isSearching { searchResults = CanvasSearch.matches(in: canvas, query: searchText) }
        let liveCategories = categoryFilter.intersection(canvas.categories.map(\.id))
        if liveCategories != categoryFilter { categoryFilter = liveCategories }
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
        var shown = snapshot
        if let drag { shown = shown.moving(drag.ids, by: drag.offset) }
        if let resize { shown = shown.resizing(resize.id, to: resize.rect, line: resize.line) }
        return shown
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
        revealPending()
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
    /// Nodes at full strength: the selection and its neighbors, and what the legend filters
    /// let through; both, when both are on. Nil means nothing is dimmed.
    var highlighted: Set<UUID>? {
        let near = selection.isEmpty ? nil : snapshot.neighbors(of: selection)
        let matches = filterMatches
        switch (near, matches) {
        case let (near?, matches?): return near.intersection(matches)
        case let (near?, nil): return near
        case let (nil, matches?): return matches
        case (nil, nil): return nil
        }
    }

    /// Lines touching these stay at full strength: the selection, else what the filters match.
    var edgeFocus: Set<UUID>? {
        if !selection.isEmpty { return selection }
        return filterMatches
    }

    var isFiltering: Bool { !categoryFilter.isEmpty || !purposeFilter.isEmpty }

    // MARK: Categories

    /// Click a legend chip to show only that category; again to show all. ⇧-click adds or removes.
    func toggleCategoryFilter(_ id: UUID, extending: Bool) {
        categoryFilter = Self.toggled(id, in: categoryFilter, extending: extending)
    }

    func togglePurposeFilter(_ purpose: PromptPurpose, extending: Bool) {
        purposeFilter = Self.toggled(purpose, in: purposeFilter, extending: extending)
    }

    func clearFilters() {
        categoryFilter = []
        purposeFilter = []
    }

    private static func toggled<T: Hashable>(_ item: T, in set: Set<T>, extending: Bool) -> Set<T> {
        if extending {
            var result = set
            if result.contains(item) { result.remove(item) } else { result.insert(item) }
            return result
        }
        return set == [item] ? [] : [item]
    }

    /// 1–9: the nth category in the legend for everything selected; 0: no category.
    func assignCategory(number: Int) {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        let categories = canvas.sortedCategories
        let category: CanvasCategory?
        if number == 0 {
            category = nil
        } else if categories.indices.contains(number - 1) {
            category = categories[number - 1]
        } else {
            Self.refuse()
            return
        }
        update { CanvasGraph.setCategory(nodes, to: category) }
    }

    func addCategory() -> CanvasCategory? {
        guard let context else { return nil }
        var made: CanvasCategory?
        update { made = CanvasGraph.addCategory(to: canvas, in: context) }
        return made
    }

    func deleteCategory(_ category: CanvasCategory) {
        guard let context else { return }
        categoryFilter.remove(category.id)
        update { CanvasGraph.deleteCategory(category, in: context) }
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
        selectedEdgeID = nil
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
        selectedEdgeID = nil
    }

    // MARK: Lines and colors

    /// The line under a point in the view, if any.
    func edgeID(at viewPoint: CGPoint) -> String? {
        snapshot.edge(near: camera.canvasPoint(viewPoint, in: viewSize), tolerance: Self.edgeTolerance / camera.zoom)?.id
    }

    var selectedEdge: CanvasSnapshot.Edge? {
        selectedEdgeID.flatMap { snapshot.edge($0) }
    }

    func selectEdge(_ id: String) {
        endEditing()
        linkSourceID = nil
        selection = []
        selectedEdgeID = id
    }

    /// The color of what's selected: the nodes' fill (Text: its words), or the line's.
    /// nil goes back to the category's color (or grey). Each change is one Undo step.
    func setColor(_ hex: String?) {
        if let edge = selectedEdge {
            let (child, link) = parts(of: edge)
            guard child != nil || link != nil else { return }
            change { CanvasGraph.setLineColor(hex, child: child, link: link) }
        } else {
            let nodes = selectedNodes
            guard !nodes.isEmpty else { return }
            change { CanvasGraph.setColor(hex, of: nodes) }
        }
    }

    /// The words of the selected Ideas, Notes and Text.
    func setTextColor(_ hex: String?) {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        change { CanvasGraph.setTextColor(hex, of: nodes) }
    }

    /// The color of what's selected, as stored: what the color dot shows.
    var selectionColorHex: String? {
        if let edge = selectedEdge { return edge.colorHex }
        guard let node = selectedNodes.first else { return nil }
        return node.kind == .text ? node.textColorHex : node.effectiveColorHex
    }

    /// A: the selected line's arrowhead on or off.
    func toggleArrow() {
        guard let edge = selectedEdge else { return }
        let (child, link) = parts(of: edge)
        guard child != nil || link != nil else { return }
        update { CanvasGraph.setArrow(!edge.hasArrow, child: child, link: link) }
    }

    /// C: the color popover for the selection or the selected line.
    func openColorPicker() {
        guard !selection.isEmpty || selectedEdgeID != nil else { return }
        showsColorPicker = true
    }

    /// Text size for every selected Text node.
    func setTextSizeOfSelection(_ size: TextSize) {
        let texts = selectedNodes.filter { $0.kind == .text }
        guard !texts.isEmpty else { return }
        update { for text in texts { CanvasGraph.edit(text) { $0.textSize = size } } }
    }

    /// Runs a change that can be refused (a color too close to focus red): saves it, or beeps.
    private func change(_ change: () -> Bool) {
        if change() {
            save()
            reload()
        } else {
            Self.refuse()
        }
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

    /// Selects just this node, e.g. before acting on it from its menu.
    func select(_ id: UUID) {
        guard editingID != id else { return }
        endEditing()
        selection = [id]
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

    /// Free text on the selected Idea (or the selected card's Idea, or the root), typed into.
    func addText() {
        add(.text)
    }

    private func add(_ kind: NodeKind) {
        endEditing()
        guard let context, let parent = anchorIdea,
              let node = CanvasGraph.addChild(kind, under: parent, body: kind == .idea ? nil : "", in: context)
        else { return }
        finishAdding(node)
    }

    /// From a detail page: a new Note, Text or Idea on that node, opened full size to write in.
    func addChild(_ kind: NodeKind, to parentID: UUID) {
        guard let context, let parent = node(parentID),
              let child = CanvasGraph.addChild(kind, under: parent, body: kind == .idea ? nil : "", in: context)
        else { return }
        save()
        reload()
        openDetail(child.id)
    }

    /// Selects the new node and starts typing into it. A Note or Text left empty isn't kept.
    private func finishAdding(_ node: CanvasNode) {
        save()
        reload()
        selection = [node.id]
        if node.kind == .note || node.kind == .text { freshID = node.id }
        beginEditing(node.id)
        reveal(node.id)
    }

    // MARK: Tools

    func setTool(_ new: CanvasTool) {
        endEditing()
        if (new == .arrow) != linkMode {
            linkMode.toggle()
            linkSourceID = nil
        }
        arrowDraft = nil
        tool = new
    }

    /// The bar's shape menu: that shape, and the Shape tool picked.
    func setShapeTool(_ shape: ShapeKind) {
        shapeTool = shape
        setTool(.shape)
    }

    /// The node under a point in the view, if any.
    func nodeID(at viewPoint: CGPoint) -> UUID? {
        snapshot.node(at: camera.canvasPoint(viewPoint, in: viewSize))?.id
    }

    /// The Sticky, Note, Text, Shape and Idea tools (and double-click): a new one loose, right
    /// where the board was clicked, typed into. The tool goes back to Select.
    func place(_ kind: NodeKind, at viewPoint: CGPoint) {
        endEditing()
        guard let context else { return }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        let node: CanvasNode = switch kind {
        case .sticky: CanvasGraph.addSticky(to: canvas, at: point, in: context)
        case .shape: CanvasGraph.addShape(shapeTool, to: canvas, at: point, in: context)
        default: CanvasGraph.addNode(kind, to: canvas, at: point, body: kind == .idea ? nil : "", in: context)
        }
        if tool != .select { setTool(.select) }
        finishAdding(node)
    }

    /// The Prompt tool: a new prompt (a Reference in the Library, with no picture yet) where the
    /// board was clicked, opened full size to write it.
    func placePrompt(at viewPoint: CGPoint) {
        endEditing()
        guard let context else { return }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        let reference = Reference(mediaFilename: "", mediaType: .image, width: 0, height: 0, origin: .mine)
        context.insert(reference)
        reference.promptRaw = ""
        reference.aiState = .done
        let node = CanvasGraph.addNode(.prompt, to: canvas, at: point, reference: reference, in: context)
        if tool != .select { setTool(.select) }
        save()
        reload()
        selection = [node.id]
        openDetail(node.id)
    }

    // MARK: Free arrows

    /// The Arrow tool dragged on empty board: the arrow follows the pointer.
    func arrowDragChanged(from viewStart: CGPoint, to viewPoint: CGPoint) {
        if arrowDraft == nil { endEditing() }
        arrowDraft = ArrowDraft(
            start: camera.canvasPoint(viewStart, in: viewSize),
            end: camera.canvasPoint(viewPoint, in: viewSize)
        )
    }

    /// Lets go of a free arrow: it stays, unless it's too short to be meant. Back to Select.
    func arrowDragEnded() {
        guard let draft = arrowDraft else { return }
        arrowDraft = nil
        addFreeArrow(from: draft.start, to: draft.end)
    }

    private func addFreeArrow(from start: CGPoint, to end: CGPoint) {
        guard let context, hypot(end.x - start.x, end.y - start.y) * camera.zoom >= 12 else { return }
        let node = CanvasGraph.addLine(from: start, to: end, on: canvas, in: context)
        setTool(.select)
        save()
        reload()
        selection = [node.id]
    }

    func toggleLibrary() {
        showsLibrary.toggle()
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
        case .note, .text, .sticky:
            editDraft = node.body ?? ""
        case .shape:
            // Arrows and lines have no words.
            guard !node.isLine else { return }
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
            case .note, .text, .sticky, .shape:
                if text != (node.body ?? "") { CanvasGraph.edit(node) { $0.body = text } }
            case .reference, .prompt:
                break
            }
        }
        if fresh, node.kind == .note || node.kind == .text,
           (node.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    // MARK: Resizing

    /// A node being resized by a corner (or an arrow by an end): its new box, in canvas points.
    private(set) var resize: Resize?

    struct Resize: Equatable {
        var id: UUID
        var rect: CGRect
        /// For an arrow or line: its new run from start to end.
        var line: CGVector?
    }

    /// Dragging a corner of the selected node. Ideas stay round, Text and pictures keep their
    /// proportions (`freeAspect`, ⇧, lets a picture stretch).
    func resizeChanged(_ id: UUID, corner: ResizeCorner, to viewPoint: CGPoint, freeAspect: Bool) {
        guard let geometry = snapshot.node(id), let resized = node(id), !resized.isLine else { return }
        if resize == nil { endEditing() }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        let keep = resized.isIdea || resized.kind == .text || (resized.kind == .reference && !freeAspect)
        resize = Resize(id: id, rect: CanvasLayout.resized(geometry.rect, corner: corner, to: point, keepingAspect: keep))
    }

    /// Dragging one end of the selected arrow or line.
    func lineEndChanged(_ id: UUID, isEnd: Bool, to viewPoint: CGPoint) {
        guard let geometry = snapshot.node(id), geometry.isLine else { return }
        if resize == nil { endEditing() }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        let start = isEnd ? geometry.lineStart : point
        let end = isEnd ? point : geometry.lineEnd
        resize = Resize(
            id: id,
            rect: CanvasLayout.lineRect(from: start, to: end),
            line: CGVector(dx: end.x - start.x, dy: end.y - start.y)
        )
    }

    /// Writes the resize: one change, one Undo step.
    func resizeEnded() {
        guard let resize else { return }
        self.resize = nil
        guard let resized = node(resize.id) else { return }
        if let line = resize.line {
            let center = CGPoint(x: resize.rect.midX, y: resize.rect.midY)
            CanvasGraph.setLine(
                resized,
                from: CGPoint(x: center.x - line.dx / 2, y: center.y - line.dy / 2),
                to: CGPoint(x: center.x + line.dx / 2, y: center.y + line.dy / 2)
            )
        } else {
            CanvasGraph.resize(resized, to: resize.rect)
        }
        save()
        reload()
    }

    /// The inspector's W × H.
    func setSize(_ size: CGSize, of id: UUID) {
        guard let resized = node(id), let geometry = snapshot.node(id) else { return }
        let rect = CGRect(
            x: geometry.center.x - size.width / 2, y: geometry.center.y - size.height / 2,
            width: max(size.width, CanvasLayout.minimumSide), height: max(size.height, CanvasLayout.minimumSide)
        )
        update { CanvasGraph.resize(resized, to: rect) }
    }

    func resetSize(of id: UUID) {
        guard let resized = node(id) else { return }
        update { CanvasGraph.resetSize(resized) }
    }

    // MARK: Text size and line style

    /// The steps − and + (and ⌥⌘= ⌥⌘−) go through.
    static let fontSizes: [Double] = [8, 10, 12, 14, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128]

    /// The letters' size of the first selected node with words.
    var selectionFontSize: Double? {
        selectedNodes.first(where: \.hasWords)?.effectiveFontSize
    }

    func setFontSize(_ size: Double) {
        let nodes = selectedNodes.filter(\.hasWords)
        guard !nodes.isEmpty else { return }
        update { CanvasGraph.setFontSize(size, of: nodes) }
    }

    /// Bigger (1) or smaller (−1) letters, to the next step.
    func stepFontSize(by step: Int) {
        guard let current = selectionFontSize else { return }
        let next = step > 0
            ? Self.fontSizes.first { $0 > current } ?? current
            : Self.fontSizes.last { $0 < current } ?? current
        if next != current { setFontSize(next) }
    }

    /// How thick the selected line or arrow is, or the selected shapes' border.
    var selectionStrokeWidth: Double? {
        if let edge = selectedEdge { return Double(edge.width ?? 2) }
        return selectedNodes.first { $0.kind == .shape }?.effectiveStrokeWidth
    }

    func setStrokeWidth(_ width: Double) {
        if let edge = selectedEdge {
            guard let link = parts(of: edge).link else { return }
            update { CanvasGraph.style(link, width: width) }
            return
        }
        let shapes = selectedNodes.filter { $0.kind == .shape }
        guard !shapes.isEmpty else { return }
        update { CanvasGraph.setStrokeWidth(width, of: shapes) }
    }

    /// Whether the selected link or arrows are dashed.
    var selectionIsDashed: Bool {
        if let edge = selectedEdge { return edge.dashed ?? (edge.type == .relatesTo) }
        return selectedNodes.contains { $0.isLine && $0.isDashed }
    }

    func toggleDashed() {
        let dashed = !selectionIsDashed
        if let edge = selectedEdge {
            guard let link = parts(of: edge).link else { return }
            update { CanvasGraph.style(link, dashed: dashed) }
            return
        }
        let lines = selectedNodes.filter(\.isLine)
        guard !lines.isEmpty else { return }
        update { CanvasGraph.setDashed(dashed, of: lines) }
    }

    /// The selected link's or arrow's arrowheads.
    func setArrowheads(start: Bool, end: Bool) {
        if let edge = selectedEdge {
            guard let link = parts(of: edge).link else { return }
            update { CanvasGraph.style(link, startArrow: start, endArrow: end) }
            return
        }
        let lines = selectedNodes.filter(\.isLine)
        guard !lines.isEmpty else { return }
        update { for line in lines { CanvasGraph.setArrowheads(of: line, start: start, end: end) } }
    }

    /// A picture on its own, or in its card.
    func setBare(_ bare: Bool, of id: UUID) {
        guard let picture = node(id) else { return }
        update { CanvasGraph.setBare(bare, of: [picture]) }
    }

    // MARK: Connecting

    /// Dragging a node's handle. Over another node, that node is the target.
    func connectChanged(from sourceID: UUID, at viewPoint: CGPoint, isLink: Bool) {
        if connect == nil { endEditing() }
        let point = camera.canvasPoint(viewPoint, in: viewSize)
        // Arrows and lines aren't things to connect to.
        let target = snapshot.node(at: point).flatMap { $0.isLine ? nil : $0.id }
        connect = Connect(sourceID: sourceID, point: point, targetID: target == sourceID ? nil : target, isLink: isLink)
    }

    /// Drops the line: the dragged node belongs to the target, or with ⌥ (or the Arrow tool)
    /// they're linked. With the Arrow tool, letting go on empty board leaves a free arrow from
    /// the node to there. Anything the rules refuse (a cycle, a duplicate) beeps and changes nothing.
    func connectEnded() {
        guard let connect else { return }
        self.connect = nil
        guard let targetID = connect.targetID else {
            if tool == .arrow, let source = snapshot.node(connect.sourceID) {
                addFreeArrow(from: source.edgePoint(toward: connect.point), to: connect.point)
            }
            return
        }
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
        arrowDraft = nil
        tool = linkMode ? .arrow : .select
    }

    func setTextSize(_ size: TextSize, of id: UUID) {
        guard let node = node(id), node.textSize != size else { return }
        update { CanvasGraph.edit(node) { $0.textSize = size } }
    }

    /// The node menu's Link To…: link mode, with this node already picked as the first.
    func startLink(from id: UUID) {
        endEditing()
        linkMode = true
        tool = .arrow
        linkSourceID = id
        selection = [id]
    }

    private func makeLink(from sourceID: UUID, to targetID: UUID) {
        guard let context, let source = node(sourceID), let target = node(targetID) else { return }
        guard !source.isLine, !target.isLine else {
            Self.refuse()
            return
        }
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

    // MARK: Views

    func setViewMode(_ mode: CanvasViewMode) {
        guard mode != viewMode else { return }
        endEditing()
        if tool != .select { setTool(.select) }
        viewMode = mode
    }

    /// Return in the Graph: back to the Map, at that node.
    func showOnMap(_ id: UUID?) {
        if let id {
            selection = [id]
            pendingRevealID = id
        }
        setViewMode(.map)
        revealPending()
    }

    func revealPending() {
        guard viewMode == .map, viewSize.width > 0, let id = pendingRevealID else { return }
        pendingRevealID = nil
        reveal(id)
    }

    /// What the legend filters let through, nil when no filter is on. The Outline dims by this
    /// alone; the selection's neighbors mean little in a list.
    var filterMatches: Set<UUID>? {
        let filtered = snapshot.matching(categories: categoryFilter, purposes: purposeFilter)
        guard let found = searchMatches else { return filtered }
        return filtered.map { $0.intersection(found) } ?? found
    }

    /// What ⌘F found, nil while the bar is closed or empty.
    var searchMatches: Set<UUID>? {
        guard isSearching, !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Set(searchResults)
    }

    // MARK: Find

    func openFind() {
        endEditing()
        isSearching = true
    }

    func closeFind() {
        isSearching = false
        searchText = ""
        searchResults = []
        searchIndex = nil
    }

    func setSearchText(_ text: String) {
        searchText = text
        searchResults = CanvasSearch.matches(in: canvas, query: text)
        searchIndex = nil
    }

    /// Return or ⌘G: the next match (⇧⌘G the previous), selected and brought into view. On the
    /// Map, a match is zoomed to at least 80% so it can be read.
    func findNext(by step: Int = 1) {
        guard !searchResults.isEmpty else {
            Self.refuse()
            return
        }
        let next = ((searchIndex ?? (step > 0 ? -1 : 0)) + step + searchResults.count) % searchResults.count
        searchIndex = next
        let id = searchResults[next]
        endEditing()
        selection = [id]
        guard viewMode == .map, let rect = snapshot.node(id)?.rect else { return }
        isAutoFitted = false
        if camera.zoom < 0.8 {
            move(to: CanvasCamera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: 0.8))
        } else {
            reveal(id)
        }
    }

    // MARK: Minimap and far zoom

    func toggleMinimap() {
        showsMinimap.toggle()
        UserDefaults.standard.set(showsMinimap, forKey: Self.minimapKey)
    }

    /// Below `CanvasLayout.blockZoom` cards are drawn as plain blocks.
    var isFarZoom: Bool { camera.zoom < CanvasLayout.blockZoom }

    /// Click or drag in the minimap: look at that canvas point.
    func center(on point: CGPoint) {
        isAutoFitted = false
        move(to: CanvasCamera(center: point, zoom: camera.zoom))
    }

    // MARK: Requests

    /// Something asked from outside the Canvas view, e.g. by the ⌘K palette.
    func perform(_ action: CanvasRequest.Action) {
        switch action {
        case .focus(let id):
            guard node(id) != nil else { return }
            while isShowingDetail { closeDetail() }
            endEditing()
            selection = [id]
            pendingRevealID = id
            revealPending()
        case .view(let mode): setViewMode(mode)
        case .addNote: addNote()
        case .addSubIdea: addSubIdea()
        case .find: openFind()
        case .toggleInspector: toggleInspector()
        case .toggleLinkMode: toggleLinkMode()
        case .toggleMinimap: toggleMinimap()
        }
    }

    // MARK: Outline

    var outlineRows: [CanvasOutline.Row] {
        CanvasOutline.rows(of: canvas, collapsed: collapsed)
    }

    func toggleCollapsed(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    /// ↑ / ↓: the row above or below the selected one.
    func stepOutline(by step: Int) {
        let rows = outlineRows
        guard !rows.isEmpty else { return }
        let current = selectedNode.flatMap { node in rows.firstIndex { $0.id == node.id } }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        endEditing()
        selection = [rows[next].id]
    }

    /// ←: fold the selected row, or if it's already folded (or has nothing under it), go to its parent.
    func collapseOrSelectParent() {
        guard let node = selectedNode else { return }
        if !node.children.isEmpty, !collapsed.contains(node.id) {
            collapsed.insert(node.id)
        } else if let parent = node.parent {
            selection = [parent.id]
        }
    }

    /// →: unfold the selected row.
    func expandSelected() {
        guard let node = selectedNode else { return }
        collapsed.remove(node.id)
    }

    /// Tab in the Outline.
    func indentSelected() {
        outlineChange { node, context in
            let done = CanvasGraph.indent(node, in: context)
            if done, let parent = node.parent { collapsed.remove(parent.id) }
            return done
        }
    }

    /// ⇧Tab in the Outline.
    func outdentSelected() {
        outlineChange { node, context in CanvasGraph.outdent(node, in: context) }
    }

    /// ⌥⌘↑ / ⌥⌘↓.
    func moveSelected(by step: Int) {
        outlineChange { node, _ in CanvasGraph.moveAmongSiblings(node, by: step) }
    }

    private func outlineChange(_ change: (CanvasNode, ModelContext) -> Bool) {
        endEditing()
        guard let context, let node = selectedNode else { return }
        if change(node, context) {
            save()
            reload()
        } else {
            Self.refuse()
        }
    }

    // MARK: Graph

    /// The board as dots and lines: Ideas bigger and labeled, cards small, seeded from where
    /// they are on the Map. Free arrows aren't dots.
    var graphModel: ForceGraphModel {
        ForceGraphModel(
            nodes: snapshot.nodes.filter { !$0.isLine }.map { node in
                ForceGraphModel.Node(
                    id: node.id,
                    label: node.title,
                    colorHex: node.colorHex,
                    radius: node.kind == .idea ? node.rect.width / 10 : 4.5,
                    seed: node.center,
                    showsLabel: node.kind == .idea
                )
            },
            edges: snapshot.edges.map { edge in
                ForceGraphModel.Edge(from: edge.from, to: edge.to, dashed: edge.type == .relatesTo)
            }
        )
    }

    // MARK: Bringing things in

    /// Where a drag from outside is: the node under it lights up.
    func dropHover(at viewPoint: CGPoint?) {
        let target = viewPoint.flatMap { snapshot.node(at: camera.canvasPoint($0, in: viewSize)) }?.id
        if target != dropTargetID { dropTargetID = target }
    }

    /// What pasted and imported things attach to: the selected node, if it can hold things.
    /// With nothing selected they land loose.
    var pasteTargetID: UUID? { selectedNode.flatMap { CanvasGraph.canHold($0) ? $0.id : nil } }


    /// ⌘V on the board: where the pointer is (or the middle of the view), onto the selected
    /// node if it can hold things.
    func paste(_ providers: [NSItemProvider]) async {
        await capture(providers, at: pointer, onto: pasteTargetID)
    }

    /// ⌘V or Paste in a node's full-size view: onto that node.
    func paste(_ providers: [NSItemProvider], onto id: UUID) async {
        await capture(providers, at: nil, onto: id)
    }

    /// Reads, prepares and places what was dropped or pasted.
    func capture(_ providers: [NSItemProvider], at viewPoint: CGPoint?, onto targetID: UUID?) async {
        let items = await CaptureService.items(from: providers)
        await capture(items, at: viewPoint, onto: targetID)
    }

    func capture(_ items: [CaptureItem], at viewPoint: CGPoint?, onto targetID: UUID?) async {
        let point = viewPoint.map { camera.canvasPoint($0, in: viewSize) } ?? camera.center
        // References dragged in from the Library panel are already in the Library.
        var existing: [UUID] = []
        var rest: [CaptureItem] = []
        for item in items {
            if case let .text(text) = item, let id = LibraryDrag.referenceID(in: text) {
                existing.append(id)
            } else {
                rest.append(item)
            }
        }
        if !existing.isEmpty { place(references: existing, at: point, onto: targetID) }
        guard !rest.isEmpty else { return }
        let prepared = await CapturePrep.prepare(rest)
        place(prepared, at: point, onto: targetID)
    }

    /// The Library panel: a picture or card for each Reference (no copy; the same Reference), on
    /// the node under the drop or the selected one, or loose where it was dropped.
    func place(references ids: [UUID], at point: CGPoint? = nil, onto targetID: UUID?) {
        let all = (try? context?.fetch(FetchDescriptor<Reference>())) ?? []
        let references = ids.compactMap { id in all.first { $0.id == id } }
        guard !references.isEmpty else { return }
        placeEach(references, at: point ?? camera.center, onto: targetID) { reference, position, idea, context in
            let node = CanvasGraph.addNode(
                reference.hasMedia ? .reference : .prompt,
                to: canvas, parent: idea, at: position, reference: reference, in: context
            )
            node.isBare = reference.hasMedia
            return node
        }
    }

    /// Puts captured things on the board, all in one Undo step. Dropped or pasted onto a node
    /// that can hold things they belong to it and take free spots around it; elsewhere they stay
    /// loose where they landed, fanned out a little.
    func place(_ prepared: [PreparedCapture], at point: CGPoint, onto targetID: UUID?) {
        guard !prepared.isEmpty else {
            Self.refuse()
            return
        }
        placeEach(prepared, at: point, onto: targetID) { item, position, idea, context in
            switch item {
            case let .link(url, title, iconFilename):
                let node = CanvasGraph.addNode(.link, to: canvas, parent: idea, at: position, title: title, in: context)
                node.urlString = url.absoluteString
                node.iconFilename = iconFilename
                return node
            case .media, .prompt:
                guard let reference = CaptureService.makeReference(item, in: context) else { return nil }
                let node = CanvasGraph.addNode(
                    reference.hasMedia ? .reference : .prompt,
                    to: canvas, parent: idea, at: position, reference: reference, in: context
                )
                // Pictures land on their own, as on a moodboard; "Show as Card" puts them in one.
                node.isBare = reference.hasMedia
                return node
            }
        }
    }

    /// Makes a node for each item, in one Undo step. Onto a node that can hold things (`CanvasGraph.canHold`)
    /// they belong to it and take free spots around it; otherwise they stay loose at `point`,
    /// fanned out a little. Selects what was made.
    private func placeEach<Item>(
        _ items: [Item],
        at point: CGPoint,
        onto targetID: UUID?,
        make: (Item, CGPoint, CanvasNode?, ModelContext) -> CanvasNode?
    ) {
        guard let context else { return }
        endEditing()
        let parent = targetID.flatMap { self.node($0) }.flatMap { CanvasGraph.canHold($0) ? $0 : nil }
        var made: [CanvasNode] = []
        for item in items {
            let offset = CGFloat(made.count) * 28
            let position = CGPoint(x: point.x + offset, y: point.y + offset)
            guard let node = make(item, position, parent, context) else { continue }
            if let parent { node.position = CanvasGraph.freeSpot(for: node, around: parent) }
            made.append(node)
        }
        save()
        reload()
        selection = Set(made.map(\.id))
        if let last = made.last { reveal(last.id) }
    }

    // MARK: Detail

    var detailItem: DetailItem? { detailPath.last }
    var isShowingDetail: Bool { !detailPath.isEmpty }

    /// Space or double-click: the node full size. From inside a detail, it goes on top.
    func openDetail(_ id: UUID? = nil) {
        // Arrows and lines have nothing to show full size.
        guard let id = id ?? selectedNode?.id, let opened = node(id), !opened.isLine else { return }
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

    /// The detail sheet swiped away (iPhone): back to the Canvas, with the last node selected.
    func closeAllDetail() {
        while isShowingDetail { closeDetail() }
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
    /// `-MotiffFilter <category name>` turns that legend filter on.
    private func applyLaunchFilter() {
        guard let name = DebugLaunchRoute.filterName,
              let category = canvas.categories.first(where: { $0.name == name })
        else { return }
        categoryFilter = [category.id]
    }

    private static var didApplyLaunchPaste = false

    /// `-MotiffPaste <text>` pastes that text onto the selected Idea once, as ⌘V would.
    func applyLaunchPaste() {
        guard !Self.didApplyLaunchPaste, let text = DebugLaunchRoute.pasteText else { return }
        Self.didApplyLaunchPaste = true
        let target = pasteTargetID
        Task { await capture([.text(text)], at: nil, onto: target) }
    }

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
