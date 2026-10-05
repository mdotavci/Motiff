import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// One Canvas, as a Map, an Outline or a Graph (⌘1 ⌘2 ⌘3), with the inspector, the full-size
/// detail and the keyboard shared between them. The Map: lines underneath, Ideas and cards on
/// top, a legend and zoom control floating over it. Drag the background (or two-finger scroll) to pan, pinch to zoom
/// around the pointer. Click selects, drag moves, Tab and ⌘Return add, Return edits in place.
struct CanvasMapView: View {
    let canvas: Canvas
    /// Asked of this Canvas from outside, e.g. by the ⌘K palette; cleared once done.
    @Binding var request: CanvasRequest?

    @State private var controller: CanvasController
    @State private var lastDrag: CGSize = .zero
    @FocusState private var mapFocused: Bool
    /// The line whose label is being typed in the Label… alert.
    @State private var labelingEdge: CanvasSnapshot.Edge?
    @State private var labelDraft = ""
    @State private var isImporting = false
    #if DEBUG
    @AppStorage("debug.fps") private var showsFrameRate = false
    #endif

    /// The Map's own coordinate space, so node drags measure against something that stays put.
    private static let space = "canvas.map"

    init(canvas: Canvas, request: Binding<CanvasRequest?> = .constant(nil)) {
        self.canvas = canvas
        _request = request
        _controller = State(initialValue: CanvasController(canvas: canvas))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            // ⌘V: images, links and prompts go onto the selected Idea (or the root).
            .onPasteCommand(of: CaptureService.acceptedTypes) { providers in
                let target = controller.pasteTargetID
                Task { await controller.capture(providers, at: nil, onto: target) }
            }
            #endif
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                let target = controller.pasteTargetID
                Task { await controller.capture(urls.map { CaptureItem.file($0) }, at: nil, onto: target) }
            }
            .focusable()
            .focused($mapFocused)
            .focusEffectDisabled()
            .onKeyPress(
                keys: [
                    .tab, .return, .delete, .deleteForward, .escape, .space,
                    .leftArrow, .rightArrow, .upArrow, .downArrow, "l", Self.backTab,
                    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                ],
                phases: [.down, .repeat]
            ) { press in
                handleKey(press)
            }
            .overlay(alignment: .top) {
                if controller.isSearching {
                    FindBar(controller: controller)
                        .padding(.top, Theme.gutter + (controller.viewMode == .outline ? 48 : 44))
                }
            }
            #if DEBUG
            .overlay(alignment: .bottom) {
                if showsFrameRate {
                    FrameRateMeter().padding(Theme.gutter)
                }
            }
            #endif
            .alert("Label", isPresented: isLabeling) {
                TextField("Label", text: $labelDraft)
                Button("Save") {
                    if let edge = labelingEdge { controller.setLabel(labelDraft, on: edge) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A word or two on the line. Leave it empty to remove the label.")
            }
            .overlay(alignment: .topLeading) {
                // The open node grows out of its place on the Map and shrinks back into it.
                ZStack {
                    if let item = controller.detailItem {
                        CanvasDetailView(controller: controller, item: item)
                            .transition(.hero(from: heroSource(for: item), in: controller.viewSize))
                    }
                }
                .animation(.snappy(duration: 0.32), value: controller.isShowingDetail)
            }
            .inspector(isPresented: Binding(get: { controller.showsInspector }, set: { controller.showsInspector = $0 })) {
                CanvasInspector(controller: controller)
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("View", selection: Binding(get: { controller.viewMode }, set: { controller.setViewMode($0) })) {
                        ForEach(CanvasViewMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Map, Outline or Graph (⌘1, ⌘2, ⌘3)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspector", systemImage: "sidebar.right", action: controller.toggleInspector)
                        .help("Show Inspector (\(ShortcutCatalog.inspector.keys))")
                }
            }
            .onAppear {
                controller.reload()
                if controller.editingID == nil { mapFocused = true }
                handleRequest()
                #if DEBUG
                controller.applyLaunchPaste()
                #endif
            }
            .onChange(of: request) { handleRequest() }
            .onChange(of: controller.isSearching) { _, searching in
                if !searching { mapFocused = true }
            }
            .onChange(of: canvas.updatedAt) { controller.reload() }
            .onChange(of: controller.editingID) { _, editing in
                // Back to the Canvas view when typing ends, so Tab and ⌫ work again.
                if editing == nil { mapFocused = true }
            }
            .onChange(of: controller.viewMode) { mapFocused = true }
            #if os(macOS)
            .onChange(of: controller.linkMode) { _, on in
                if on { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if controller.linkMode { NSCursor.pop() }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in controller.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in controller.reload() }
            .focusedSceneValue(\.importFiles, ImportAction { isImporting = true })
            .focusedSceneValue(\.canvasZoom, controller.viewMode == .map ? CanvasZoomActions(
                zoomIn: controller.zoomIn,
                zoomOut: controller.zoomOut,
                fit: controller.fitToContent
            ) : nil)
            .focusedSceneValue(\.canvasEditing, CanvasEditActions(
                hasSelection: !controller.selection.isEmpty,
                showsInspector: controller.showsInspector,
                addNote: controller.addNote,
                addSubIdea: controller.addSubIdea,
                edit: { controller.beginEditing() },
                delete: { controller.deleteSelection(branch: false) },
                deleteBranch: { controller.deleteSelection(branch: true) },
                toggleInspector: controller.toggleInspector,
                linkMode: controller.linkMode,
                toggleLinkMode: controller.toggleLinkMode,
                canOpen: controller.selectedNode != nil && !controller.isShowingDetail,
                open: { controller.openDetail() },
                canCopyPrompt: controller.promptToCopy != nil,
                copyPrompt: controller.copyPrompt,
                viewMode: controller.viewMode,
                setViewMode: controller.setViewMode,
                find: controller.openFind,
                findNext: { controller.findNext() },
                findPrevious: { controller.findNext(by: -1) },
                canFindNext: !controller.searchResults.isEmpty,
                showsMinimap: controller.showsMinimap,
                toggleMinimap: controller.toggleMinimap
            ))
            .navigationTitle(canvas.displayTitle)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.viewMode {
        case .map:
            map
        case .outline:
            VStack(alignment: .leading, spacing: 0) {
                CategoryLegend(controller: controller)
                    .padding(Theme.gutter)
                CanvasOutlineView(controller: controller) { mapFocused = true }
            }
            .background(.background)
        case .graph:
            ForceGraphView(
                model: controller.graphModel,
                selection: controller.selection,
                highlighted: controller.highlighted
            ) { id, extending in
                if let id { controller.tap(id, extending: extending) } else { controller.clearSelection() }
                mapFocused = true
            } onOpen: { id in
                controller.openDetail(id)
            }
            .overlay(alignment: .topLeading) {
                CategoryLegend(controller: controller)
                    .padding(Theme.gutter)
            }
        }
    }

    /// The Map: lines, nodes, handles, the line being drawn; legend, zoom and link-mode pill on top.
    private var map: some View {
        let camera = controller.camera
        let size = controller.viewSize
        let shown = controller.displayedSnapshot
        let dragging = controller.drag?.ids ?? []
        let highlighted = controller.highlighted
        let targetID = controller.connect?.targetID
        let visible = controller.visibleNodes(in: shown)
        let far = controller.isFarZoom
        return ZStack(alignment: .topLeading) {
            Theme.canvasGround
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.clearSelection()
                    mapFocused = true
                }

            EdgeLayer(
                snapshot: shown,
                camera: camera,
                hoveredEdgeID: controller.hoveredEdgeID,
                focus: controller.edgeFocus
            )

            if far {
                BlockLayer(nodes: visible, camera: camera, highlighted: highlighted)
            }

            ForEach(visible) { geometry in
                if let node = controller.node(geometry.id) {
                    placedNode(
                        node,
                        geometry: geometry,
                        camera: camera,
                        size: size,
                        isDragging: dragging.contains(node.id),
                        isTarget: node.id == targetID || node.id == controller.linkSourceID
                            || node.id == controller.dropTargetID,
                        isHovered: node.id == controller.hoveredNodeID,
                        isDimmed: highlighted.map { !$0.contains(node.id) } ?? false,
                        isFar: far
                    )
                }
            }

            if let connect = controller.connect, let source = shown.node(connect.sourceID) {
                ConnectLine(
                    start: camera.screenPoint(source.edgePoint(toward: connect.point), in: size),
                    end: camera.screenPoint(connect.point, in: size),
                    isLink: connect.isLink
                )
            }

            ForEach(handleIDs, id: \.self) { id in
                if let geometry = shown.node(id) {
                    handle(for: geometry, camera: camera, size: size)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.setViewSize($0) }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): controller.setPointer(location)
            case .ended: controller.setPointer(nil)
            }
        }
        .gesture(panGesture)
        #if os(macOS)
        .modifier(ScrollZoomMonitor(controller: controller))
        #endif
        .onDrop(of: CaptureService.acceptedTypes, delegate: CanvasDropDelegate(controller: controller))
        .overlay(alignment: .topLeading) {
            CategoryLegend(controller: controller)
                .padding(Theme.gutter)
        }
        .overlay(alignment: .bottomTrailing) {
            ZoomControl(controller: controller)
                .padding(Theme.gutter)
        }
        .overlay(alignment: .bottomLeading) {
            if controller.showsMinimap, !controller.snapshot.nodes.isEmpty {
                Minimap(controller: controller)
                    .padding(Theme.gutter)
            }
        }
        .overlay(alignment: .top) {
            if controller.linkMode {
                LinkModePill(hasSource: controller.linkSourceID != nil)
                    .padding(.top, Theme.gutter + 44)
            }
        }
        .contextMenu {
            if let edge = controller.hoveredEdge {
                edgeMenu(edge)
            }
        }
        .onAppear { controller.revealPending() }
    }

    private func handleRequest() {
        guard let request, request.canvasID == canvas.id else { return }
        self.request = nil
        controller.perform(request.action)
    }

    /// ⇧Tab arrives as the back-tab character.
    private static var backTab: KeyEquivalent { KeyEquivalent("\u{19}") }

    /// One node at canvas scale, scaled and placed on screen, with its selection ring and the
    /// lift while it's dragged.
    private func placedNode(
        _ node: CanvasNode,
        geometry: CanvasSnapshot.Node,
        camera: CanvasCamera,
        size: CGSize,
        isDragging: Bool,
        isTarget: Bool,
        isHovered: Bool,
        isDimmed: Bool,
        isFar: Bool
    ) -> some View {
        let isEditing = controller.editingID == node.id
        let isSelected = controller.selection.contains(node.id)
        // While typing, clicks and drags belong to the text field.
        let mask: GestureMask = isEditing ? .subviews : .all
        return Group {
            if isFar && !isEditing {
                // Drawn by the BlockLayer; this only takes clicks and drags.
                Color.clear
            } else {
                NodeView(
                    node: node,
                    size: geometry.rect.size,
                    zoom: camera.zoom,
                    editor: isEditing ? controller : nil,
                    isPlaying: isHovered && controller.drag == nil
                )
            }
        }
            .frame(width: geometry.rect.width, height: geometry.rect.height)
            .overlay {
                if isSelected || isTarget {
                    SelectionRing(isIdea: node.isIdea, zoom: camera.zoom)
                }
            }
            .opacity(isDimmed ? 0.3 : 1)
            // The one elevation in the app: something picked up.
            .shadow(color: .black.opacity(isDragging ? 0.28 : 0), radius: isDragging ? 14 : 0, y: isDragging ? 8 : 0)
            .contentShape(node.isIdea ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Theme.cardCorner)))
            .gesture(TapGesture().onEnded {
                controller.tap(node.id, extending: Self.shiftIsDown)
                if controller.editingID == nil { mapFocused = true }
            }, including: mask)
            .simultaneousGesture(TapGesture(count: 2).onEnded { controller.beginEditing(node.id) }, including: mask)
            .gesture(nodeDrag(node.id), including: mask)
            .scaleEffect(camera.zoom)
            .position(camera.screenPoint(geometry.center, in: size))
            .zIndex(isDragging ? 1 : 0)
    }

    /// Nodes that show a connection handle: the one under the pointer and a single selected one,
    /// or only the source while a line is being drawn.
    private var handleIDs: [UUID] {
        if let connect = controller.connect { return [connect.sourceID] }
        guard controller.editingID == nil, controller.drag == nil, !controller.linkMode else { return [] }
        var ids: [UUID] = []
        if let hovered = controller.hoveredNodeID { ids.append(hovered) }
        if let selected = controller.selectedNode?.id, selected != controller.hoveredNodeID { ids.append(selected) }
        return ids
    }

    /// A small circle on a node's right edge. Drag it onto another node to make this one belong
    /// to it; ⌥-drag to link the two instead. Same size at every zoom.
    private func handle(for geometry: CanvasSnapshot.Node, camera: CanvasCamera, size: CGSize) -> some View {
        let id = geometry.id
        return Circle()
            .fill(Theme.cardSurface)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .padding(6)
            .contentShape(Circle())
            .position(camera.screenPoint(CGPoint(x: geometry.rect.maxX, y: geometry.rect.midY), in: size))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        controller.connectChanged(from: id, at: value.location, isLink: Self.optionIsDown)
                    }
                    .onEnded { _ in controller.connectEnded() }
            )
            .help("Drag onto another node to put this under it. ⌥-drag to link them.")
            .accessibilityLabel("Connection handle")
    }

    @ViewBuilder
    private func edgeMenu(_ edge: CanvasSnapshot.Edge) -> some View {
        Button("Label…") {
            labelDraft = edge.label ?? ""
            labelingEdge = edge
        }
        Button(edge.type == .belongsTo ? "Change to Relates To" : "Change to Belongs To") {
            controller.convert(edge)
        }
        Divider()
        Button(edge.type == .belongsTo ? "Detach" : "Delete Link", role: .destructive) {
            controller.deleteEdge(edge)
        }
    }

    private func heroSource(for item: CanvasController.DetailItem) -> CGRect? {
        guard controller.viewMode == .map, case let .node(id) = item else { return nil }
        return controller.screenRect(of: id)
    }

    private var isLabeling: Binding<Bool> {
        Binding { labelingEdge != nil } set: { if !$0 { labelingEdge = nil } }
    }

    private func nodeDrag(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                controller.dragChanged(id, translation: value.translation, alone: Self.optionIsDown)
            }
            .onEnded { _ in controller.dragEnded() }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height
                )
                lastDrag = value.translation
                controller.pan(by: delta)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    /// Keys the Map handles itself. While a text field has the keyboard they're left to it.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard controller.editingID == nil else { return .ignored }
        if controller.isSearching, press.key == .escape {
            controller.closeFind()
            return .handled
        }
        if controller.isShowingDetail {
            switch press.key {
            case .escape, .space: controller.closeDetail()
            case .leftArrow: controller.stepDetail(by: -1)
            case .rightArrow: controller.stepDetail(by: 1)
            default: return .ignored
            }
            return .handled
        }
        let command = press.modifiers.contains(.command)
        let plain = press.modifiers.isDisjoint(with: [.command, .shift, .option, .control])
        if plain, let number = press.key.character.wholeNumberValue {
            controller.assignCategory(number: number)
            return .handled
        }
        if controller.viewMode == .outline, let handled = handleOutlineKey(press) {
            return handled
        }
        if controller.viewMode == .graph, press.key == .return, plain {
            controller.showOnMap(controller.selectedNode?.id)
            return .handled
        }
        switch press.key {
        case .tab where plain:
            controller.addNote()
        case .return where command:
            controller.addSubIdea()
        case .return where plain:
            controller.beginEditing()
        case .delete, .deleteForward:
            controller.deleteSelection(branch: command)
        case "l" where plain:
            controller.toggleLinkMode()
        case .space where plain:
            controller.openDetail()
        case .escape:
            if controller.linkMode {
                controller.toggleLinkMode()
            } else if controller.selection.isEmpty, controller.isFiltering {
                controller.clearFilters()
            } else {
                controller.clearSelection()
            }
        default:
            return .ignored
        }
        return .handled
    }

    /// The Outline's own keys; nil for anything it leaves to the shared ones.
    private func handleOutlineKey(_ press: KeyPress) -> KeyPress.Result? {
        let modifiers = press.modifiers.intersection([.command, .shift, .option, .control])
        switch press.key {
        case .upArrow where modifiers == [.command, .option]:
            controller.moveSelected(by: -1)
        case .downArrow where modifiers == [.command, .option]:
            controller.moveSelected(by: 1)
        case .upArrow where modifiers.isEmpty:
            controller.stepOutline(by: -1)
        case .downArrow where modifiers.isEmpty:
            controller.stepOutline(by: 1)
        case .leftArrow where modifiers.isEmpty:
            controller.collapseOrSelectParent()
        case .rightArrow where modifiers.isEmpty:
            controller.expandSelected()
        case .tab where modifiers.isEmpty:
            controller.indentSelected()
        case .tab where modifiers == .shift, Self.backTab:
            controller.outdentSelected()
        default:
            return nil
        }
        return .handled
    }

    private static var shiftIsDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }

    private static var optionIsDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.option)
        #else
        false
        #endif
    }
}

/// Files, images, links and text dragged in from outside. The node under the pointer lights up;
/// dropping on an Idea (or one of its cards) attaches to that Idea, elsewhere leaves them loose.
private struct CanvasDropDelegate: DropDelegate {
    let controller: CanvasController

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: CaptureService.acceptedTypes)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        controller.dropHover(at: info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        controller.dropHover(at: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: CaptureService.acceptedTypes)
        let location = info.location
        let target = controller.dropTargetID
        let controller = controller
        controller.dropHover(at: nil)
        Task { await controller.capture(providers, at: location, onto: target) }
        return true
    }
}

/// The line following the pointer while connecting: solid for belonging, dashed for a link.
private struct ConnectLine: View {
    let start: CGPoint
    let end: CGPoint
    let isLink: Bool

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            Color.primary.opacity(0.6),
            style: StrokeStyle(lineWidth: isLink ? 2 : 1.5, lineCap: .round, dash: isLink ? [6, 5] : [])
        )
        .allowsHitTesting(false)
    }
}

/// Shown while L link mode is on.
private struct LinkModePill: View {
    let hasSource: Bool

    var body: some View {
        Text(hasSource ? "Link mode · now click the node to link to · esc to stop" : "Link mode · click two nodes · esc to stop")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Theme.cardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// A focus-red outline a few points outside a selected node, the same width at every zoom.
private struct SelectionRing: View {
    let isIdea: Bool
    let zoom: CGFloat

    var body: some View {
        let gap = 4 / zoom
        let width = 2 / zoom
        Group {
            if isIdea {
                Circle().inset(by: -gap).stroke(Theme.accent, lineWidth: width)
            } else {
                RoundedRectangle(cornerRadius: Theme.cardCorner).inset(by: -gap).stroke(Theme.accent, lineWidth: width)
            }
        }
        .allowsHitTesting(false)
    }
}

/// − 85% + in the corner. Clicking the percentage fits the Canvas to the window.
private struct ZoomControl: View {
    let controller: CanvasController

    var body: some View {
        HStack(spacing: 0) {
            Button("Zoom Out", systemImage: "minus", action: controller.zoomOut)
                .help("Zoom out (⌘−)")
            Button(action: controller.fitToContent) {
                Text(verbatim: "\(Int((controller.camera.zoom * 100).rounded()))%")
            }
            .help("Fit to screen (⌘0)")
                .frame(minWidth: 44)
            Button("Zoom In", systemImage: "plus", action: controller.zoomIn)
                .help("Zoom in (⌘+)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}
