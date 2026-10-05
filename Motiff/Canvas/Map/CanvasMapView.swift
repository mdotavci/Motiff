import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import PhotosUI
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
    /// The pinch so far, so each change zooms by the step since the last one.
    @State private var lastMagnification: CGFloat = 1
    @FocusState private var mapFocused: Bool
    /// The line whose label is being typed in the Label… alert.
    @State private var labelingEdge: CanvasSnapshot.Edge?
    @State private var labelDraft = ""
    @State private var isImporting = false
    /// Where the Image tool was clicked, for the files the picker brings back; nil for ⌘O.
    @State private var importPoint: CGPoint?
    #if os(macOS)
    /// The cursor pushed for the current tool, popped when the tool changes.
    @State private var hasToolCursor = false
    #else
    @State private var showsPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    #endif
    #if DEBUG
    @AppStorage("debug.fps") private var showsFrameRate = false
    #endif

    /// The Map's own coordinate space, so node drags measure against something that stays put.
    private static let space = "canvas.map"

    /// `viewMode`: what it opens as; the Map on the Mac, the Outline on iPhone.
    init(canvas: Canvas, request: Binding<CanvasRequest?> = .constant(nil), viewMode: CanvasViewMode = .map) {
        self.canvas = canvas
        _request = request
        _controller = State(initialValue: CanvasController(canvas: canvas, viewMode: viewMode))
    }

    var body: some View {
        values(observers(chrome(panels(overlays(keys(pickers(framedContent)))))))
    }

    private var framedContent: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            // ⌘V: images, links and prompts go onto the selected Idea (or the root).
            .onPasteCommand(of: CaptureService.acceptedTypes) { providers in
                let target = controller.pasteTargetID
                Task { await controller.capture(providers, at: nil, onto: target) }
            }
            #endif
    }

    /// File, photo and Library pickers.
    private func pickers(_ content: some View) -> some View {
        content
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
                let point = importPoint
                importPoint = nil
                guard case let .success(urls) = result else { return }
                // The Image tool: where it was clicked, on the Idea there if any. ⌘O: the selected Idea.
                let target: UUID? = if let point { controller.nodeID(at: point) } else { controller.pasteTargetID }
                Task { await controller.capture(urls.map { CaptureItem.file($0) }, at: point, onto: target) }
            }
            #if os(iOS)
            .photosPicker(isPresented: $showsPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                let target = controller.pasteTargetID
                Task { await controller.capture(await CaptureService.items(from: items), at: nil, onto: target) }
            }
            .sheet(isPresented: Binding(get: { controller.showsLibrary }, set: { controller.showsLibrary = $0 })) {
                LibraryDrawer { reference in
                    controller.place(references: [reference.id], onto: controller.pasteTargetID)
                    controller.showsLibrary = false
                }
                .presentationDetents([.medium, .large])
            }
            #endif
    }

    /// The keyboard: focus and keys.
    private func keys(_ content: some View) -> some View {
        content
            .focusable()
            .focused($mapFocused)
            .focusEffectDisabled()
            .onKeyPress(
                keys: [
                    .tab, .return, .delete, .deleteForward, .escape, .space,
                    .leftArrow, .rightArrow, .upArrow, .downArrow, "l", Self.backTab,
                    "v", "h", "s", "n", "t", "p", "i", "r", "a", "A", "o", "c",
                    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                ],
                phases: [.down, .repeat]
            ) { press in
                handleKey(press)
            }
    }

    /// The find bar and the frame-rate readout.
    private func overlays(_ content: some View) -> some View {
        content
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
    }

    /// The label alert, the open node, and the inspector.
    private func panels(_ content: some View) -> some View {
        content
            .alert("Label", isPresented: isLabeling) {
                TextField("Label", text: $labelDraft)
                Button("Save") {
                    if let edge = labelingEdge { controller.setLabel(labelDraft, on: edge) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A word or two on the line. Leave it empty to remove the label.")
            }
            #if os(macOS)
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
            #else
            // On iPhone the open node is a sheet over the whole screen; swipe down to go back.
            .sheet(isPresented: Binding(get: { controller.isShowingDetail }, set: { if !$0 { controller.closeAllDetail() } })) {
                if let item = controller.detailItem {
                    CanvasDetailView(controller: controller, item: item)
                        .presentationDetents([.large])
                }
            }
            #endif
            #if os(macOS)
            .inspector(isPresented: Binding(get: { controller.showsInspector }, set: { controller.showsInspector = $0 })) {
                CanvasInspector(controller: controller)
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
            }
            #else
            // On iPhone the inspector is a sheet: half height, pull up for all of it.
            .sheet(isPresented: Binding(get: { controller.showsInspector }, set: { controller.showsInspector = $0 })) {
                CanvasInspector(controller: controller)
                    .presentationDetents([.medium, .large])
            }
            #endif
    }

    /// Toolbar.
    private func chrome(_ content: some View) -> some View {
        content
            .toolbar { toolbar }
    }

    /// Appearing, and keeping up with changes and undo.
    private func observers(_ content: some View) -> some View {
        content
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
            .onChange(of: controller.tool) { _, tool in
                if hasToolCursor { NSCursor.pop() }
                hasToolCursor = tool != .select
                switch tool {
                case .select: break
                case .hand: NSCursor.openHand.push()
                case .sticky, .note, .text, .prompt, .image, .shape, .arrow, .idea: NSCursor.crosshair.push()
                }
            }
            .onDisappear {
                if hasToolCursor { NSCursor.pop() }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in controller.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in controller.reload() }
    }

    /// Menu actions (the Mac's menu bar), and the title. Not on iPhone: nothing reads them there,
    /// and publishing fresh actions on every update kept the view re-rendering before its first frame.
    private func values(_ content: some View) -> some View {
        content
            #if os(macOS)
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
                addText: controller.addText,
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
                toggleMinimap: controller.toggleMinimap,
                tool: controller.tool,
                setTool: controller.setTool,
                showsLibrary: controller.showsLibrary,
                toggleLibrary: controller.toggleLibrary,
                hasWords: controller.selectionFontSize != nil,
                biggerText: { controller.stepFontSize(by: 1) },
                smallerText: { controller.stepFontSize(by: -1) }
            ))
            #endif
            .navigationTitle(canvas.displayTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            viewPicker
                .help("Map, Outline or Graph (⌘1, ⌘2, ⌘3)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.right", action: controller.toggleInspector)
                .help("Show Inspector (\(ShortcutCatalog.inspector.keys))")
        }
        #else
        ToolbarItem(placement: .principal) {
            viewPicker
                .labelStyle(.iconOnly)
                .frame(width: 150)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "info.circle", action: controller.toggleInspector)
        }
        #endif
    }

    private var viewPicker: some View {
        Picker("View", selection: Binding(get: { controller.viewMode }, set: { controller.setViewMode($0) })) {
            ForEach(CanvasViewMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.viewMode {
        case .map:
            map
        case .outline:
            VStack(alignment: .leading, spacing: 0) {
                legend
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
                legend
            }
        }
    }

    /// Along the bottom of the Map: the tool bar in the middle, the minimap and zoom at the sides.
    /// On iPhone there's no room side by side, so the minimap and zoom sit above the bar.
    @ViewBuilder
    private var bottomControls: some View {
        let sides = HStack(alignment: .bottom) {
            if controller.showsMinimap, !controller.snapshot.nodes.isEmpty {
                Minimap(controller: controller)
            }
            Spacer(minLength: 0)
            ZoomControl(controller: controller)
        }
        #if os(iOS)
        VStack(spacing: Theme.unit) {
            sides
            ToolBar(controller: controller, pickPhotos: { showsPhotos = true }, pickFiles: { isImporting = true })
        }
        .padding(Theme.gutter)
        #else
        ZStack(alignment: .bottom) {
            sides
            ToolBar(controller: controller)
        }
        .padding(Theme.gutter)
        #endif
    }

    /// The categories and purposes bar. On iPhone it scrolls sideways when it doesn't fit.
    @ViewBuilder
    private var legend: some View {
        #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
            CategoryLegend(controller: controller)
                .padding(Theme.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        #else
        CategoryLegend(controller: controller)
            .padding(Theme.gutter)
        #endif
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
                // Double-click empty space: a Note right there.
                .onTapGesture(count: 2, coordinateSpace: .named(Self.space)) { location in
                    if controller.tool == .select { controller.place(.note, at: location) }
                }
                .onTapGesture(count: 1, coordinateSpace: .named(Self.space)) { location in
                    guard !useTool(at: location) else { return }
                    // A click on a line selects it; anywhere else clears.
                    if controller.tool == .select, let edge = controller.edgeID(at: location) {
                        controller.selectEdge(edge)
                    } else {
                        controller.clearSelection()
                    }
                    mapFocused = true
                }

            EdgeLayer(
                snapshot: shown,
                camera: camera,
                hoveredEdgeID: controller.hoveredEdgeID,
                selectedEdgeID: controller.selectedEdgeID,
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

            if let draft = controller.arrowDraft {
                DraftArrow(start: camera.screenPoint(draft.start, in: size), end: camera.screenPoint(draft.end, in: size))
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

            if let id = resizableID, let geometry = shown.node(id) {
                resizeHandles(for: geometry, camera: camera, size: size)
            }

            if let anchor = selectionBarAnchor(in: shown, camera: camera, size: size) {
                SelectionBar(controller: controller) { edge in
                    labelDraft = edge.label ?? ""
                    labelingEdge = edge
                }
                .position(anchor)
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
        #else
        .simultaneousGesture(pinchGesture)
        #endif
        .onDrop(of: CaptureService.acceptedTypes, delegate: CanvasDropDelegate(controller: controller))
        .overlay(alignment: .topLeading) {
            legend
        }
        .overlay(alignment: .bottom) {
            bottomControls
        }
        #if os(macOS)
        .overlay(alignment: .trailing) {
            if controller.showsLibrary {
                LibraryDrawer { reference in
                    controller.place(references: [reference.id], onto: controller.pasteTargetID)
                } close: {
                    controller.showsLibrary = false
                }
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .background(Theme.cardSurface)
                .overlay(alignment: .leading) { Divider() }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.2), value: controller.showsLibrary)
        #endif
        .overlay(alignment: .top) {
            if controller.linkMode {
                LinkModePill(hasSource: controller.linkSourceID != nil, stop: controller.toggleLinkMode)
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

    /// Where the selection bar sits: centered above the selected nodes, or above the middle of
    /// the selected line. Nil while there's nothing to show it for, or while typing or dragging.
    private func selectionBarAnchor(in shown: CanvasSnapshot, camera: CanvasCamera, size: CGSize) -> CGPoint? {
        guard controller.editingID == nil, controller.drag == nil, controller.connect == nil,
              !controller.linkMode, !controller.isShowingDetail
        else { return nil }
        let top: CGPoint
        if let edge = controller.selectedEdge, let segment = shown.segment(of: edge) {
            top = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        } else {
            let rects = controller.selection.compactMap { shown.node($0)?.rect }
            guard let first = rects.first else { return nil }
            let union = rects.dropFirst().reduce(first) { $0.union($1) }
            top = CGPoint(x: union.midX, y: union.minY)
        }
        let point = camera.screenPoint(top, in: size)
        // Above it, kept inside the view.
        return CGPoint(
            x: min(max(point.x, 140), max(size.width - 140, 140)),
            y: max(point.y - 34, 28)
        )
    }

    /// Big enough for a finger on iPhone.
    #if os(iOS)
    private static let handleSize: CGFloat = 22
    #else
    private static let handleSize: CGFloat = 12
    #endif

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
        // Text grows as it's typed; everything else keeps its size.
        let frame = isEditing && node.kind == .text
            ? CanvasLayout.textBox(for: controller.editDraft, fontSize: node.effectiveFontSize)
            : geometry.rect.size
        // While typing, clicks and drags belong to the text field.
        let mask: GestureMask = isEditing ? .subviews : .all
        return Group {
            if isFar && !isEditing {
                // Drawn by the BlockLayer; this only takes clicks and drags.
                Color.clear
            } else {
                NodeView(
                    node: node,
                    size: frame,
                    zoom: camera.zoom,
                    editor: isEditing ? controller : nil,
                    isPlaying: isHovered && controller.drag == nil,
                    line: geometry.isLine ? geometry.line : nil
                )
            }
        }
            .frame(width: frame.width, height: frame.height)
            .overlay {
                if node.isLine {
                    if isSelected { LineSelection(node: node, size: frame, zoom: camera.zoom) }
                } else if isSelected || isTarget {
                    SelectionRing(isIdea: node.isIdea, zoom: camera.zoom)
                }
            }
            .opacity(isDimmed ? 0.3 : 1)
            // The one elevation in the app: something picked up.
            .shadow(color: .black.opacity(isDragging ? 0.28 : 0), radius: isDragging ? 14 : 0, y: isDragging ? 8 : 0)
            .contentShape(Self.hitShape(of: node, size: frame))
            // Right-click on the Mac, long-press on iPhone.
            .contextMenu {
                if !isEditing { NodeMenu(node: node, controller: controller) }
            }
            .gesture(TapGesture().onEnded {
                // An adding tool clicked on a node adds to that node's Idea.
                guard !useTool(at: camera.screenPoint(geometry.center, in: size)) else { return }
                controller.tap(node.id, extending: Self.shiftIsDown)
                if controller.editingID == nil { mapFocused = true }
            }, including: mask)
            .simultaneousGesture(TapGesture(count: 2).onEnded { controller.beginEditing(node.id) }, including: mask)
            .gesture(nodeDrag(node.id), including: mask)
            .scaleEffect(camera.zoom)
            .position(camera.screenPoint(geometry.center, in: size))
            .zIndex(isDragging ? 1 : 0)
    }

    /// What takes clicks: the circle of an Idea, the shape of a shape, the line itself for an
    /// arrow, the card for anything else.
    private static func hitShape(of node: CanvasNode, size: CGSize) -> AnyShape {
        switch node.kind {
        case .idea: return AnyShape(Circle())
        case .shape where node.isLine:
            let line = node.line
            let start = CGPoint(x: size.width / 2 - line.dx / 2, y: size.height / 2 - line.dy / 2)
            let end = CGPoint(x: size.width / 2 + line.dx / 2, y: size.height / 2 + line.dy / 2)
            return AnyShape(LineShape(start: start, end: end).stroke(style: StrokeStyle(lineWidth: CanvasLayout.linePadding * 2)))
        case .shape: return AnyShape(BoxShape(kind: node.shape))
        default: return AnyShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        }
    }

    /// Nodes that show a connection handle: the one under the pointer and a single selected one,
    /// or only the source while a line is being drawn.
    private var handleIDs: [UUID] {
        if let connect = controller.connect { return [connect.sourceID] }
        guard controller.editingID == nil, controller.drag == nil, controller.tool == .select else { return [] }
        var ids: [UUID] = []
        if let hovered = controller.hoveredNodeID { ids.append(hovered) }
        if let selected = controller.selectedNode?.id, selected != controller.hoveredNodeID { ids.append(selected) }
        // Arrows and lines don't connect to things.
        return ids.filter { controller.node($0)?.isLine != true }
    }

    /// The one selected node, when it can be resized right now.
    private var resizableID: UUID? {
        guard controller.editingID == nil, controller.drag == nil, controller.connect == nil,
              controller.tool == .select, !controller.isFarZoom
        else { return nil }
        return controller.selectedNode?.id
    }

    /// Squares on the selected node's corners to resize it (⇧ lets a picture stretch); for an
    /// arrow or line, a circle on each end to move it. Same size at every zoom.
    @ViewBuilder
    private func resizeHandles(for geometry: CanvasSnapshot.Node, camera: CanvasCamera, size: CGSize) -> some View {
        let id = geometry.id
        if geometry.isLine {
            ForEach([false, true], id: \.self) { isEnd in
                ResizeHandle(isRound: true)
                    .position(camera.screenPoint(isEnd ? geometry.lineEnd : geometry.lineStart, in: size))
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                            .onChanged { value in controller.lineEndChanged(id, isEnd: isEnd, to: value.location) }
                            .onEnded { _ in controller.resizeEnded() }
                    )
                    .help("Drag to move this end")
            }
        } else {
            ForEach(ResizeCorner.allCases, id: \.self) { corner in
                ResizeHandle(isRound: false)
                    .position(camera.screenPoint(corner.point(on: geometry.rect), in: size))
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                            .onChanged { value in
                                controller.resizeChanged(id, corner: corner, to: value.location, freeAspect: Self.shiftIsDown)
                            }
                            .onEnded { _ in controller.resizeEnded() }
                    )
                    .help("Drag to resize. Pictures keep their shape; ⇧ lets them stretch.")
            }
        }
    }

    /// A small circle on a node's right edge. Drag it onto another node to make this one belong
    /// to it; ⌥-drag to link the two instead. Same size at every zoom.
    private func handle(for geometry: CanvasSnapshot.Node, camera: CanvasCamera, size: CGSize) -> some View {
        let id = geometry.id
        return Circle()
            .fill(Theme.cardSurface)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5))
            .frame(width: Self.handleSize, height: Self.handleSize)
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
        Menu("Color") {
            ForEach(CanvasCategory.swatches, id: \.hex) { swatch in
                Button(swatch.name) {
                    controller.selectEdge(edge.id)
                    controller.setColor(swatch.hex)
                }
            }
            Divider()
            Button("Grey") {
                controller.selectEdge(edge.id)
                controller.setColor(nil)
            }
        }
        Button(edge.hasArrow ? "Hide Arrow" : "Show Arrow") {
            controller.selectEdge(edge.id)
            controller.toggleArrow()
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
                // With the Hand, dragging a node moves the view, not the node; with the Arrow it
                // draws a link from it.
                if controller.tool == .hand {
                    panStep(to: value.translation)
                } else if controller.tool == .arrow, controller.node(id)?.isLine != true {
                    controller.connectChanged(from: id, at: value.location, isLink: true)
                } else {
                    controller.dragChanged(id, translation: value.translation, alone: Self.optionIsDown)
                }
            }
            .onEnded { _ in
                lastDrag = .zero
                if controller.connect != nil {
                    controller.connectEnded()
                } else {
                    controller.dragEnded()
                }
            }
    }

    /// Dragging the background pans; with the Arrow tool it draws a free arrow instead.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if controller.tool == .arrow {
                    controller.arrowDragChanged(from: value.startLocation, to: value.location)
                } else {
                    panStep(to: value.translation)
                }
            }
            .onEnded { _ in
                lastDrag = .zero
                controller.arrowDragEnded()
            }
    }

    /// Pans by how far the drag went since the last step.
    private func panStep(to translation: CGSize) {
        let delta = CGSize(width: translation.width - lastDrag.width, height: translation.height - lastDrag.height)
        lastDrag = translation
        controller.pan(by: delta)
    }

    /// A click on the board with an adding tool: the sticky, note, text, shape, Idea or prompt
    /// goes there, or the image picker opens for there. False when the tool doesn't add
    /// (Select, Hand, Arrow).
    private func useTool(at location: CGPoint) -> Bool {
        if let kind = controller.tool.adds {
            controller.place(kind, at: location)
            return true
        }
        if controller.tool == .prompt {
            controller.placePrompt(at: location)
            return true
        }
        guard controller.tool == .image else { return false }
        importPoint = location
        controller.setTool(.select)
        isImporting = true
        return true
    }

    /// Two fingers on iPhone: zoom around where the pinch started.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                controller.zoom(by: value.magnification / lastMagnification, at: value.startLocation)
                lastMagnification = value.magnification
            }
            .onEnded { _ in lastMagnification = 1 }
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
        let shiftOnly = press.modifiers.intersection([.command, .shift, .option, .control]) == .shift
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
        if controller.viewMode == .map, plain,
           let tool = CanvasTool.allCases.first(where: { $0.key == press.key.character }) {
            controller.setTool(tool)
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
            if let edge = controller.selectedEdge {
                controller.deleteEdge(edge)
            } else {
                controller.deleteSelection(branch: command)
            }
        case "c" where plain:
            controller.openColorPicker()
        case "a" where shiftOnly, "A" where shiftOnly:
            controller.toggleArrow()
        case "l" where plain:
            controller.toggleLinkMode()
        case .space where plain:
            controller.openDetail()
        case .escape:
            if controller.tool != .select {
                controller.setTool(.select)
            } else if controller.linkMode {
                controller.toggleLinkMode()
            } else if controller.selectedEdgeID != nil {
                controller.clearSelection()
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
    let stop: () -> Void

    var body: some View {
        #if os(iOS)
        // No Esc key on a phone: the pill itself stops it.
        Button(action: stop) {
            HStack(spacing: 8) {
                Text(hasSource ? "Arrow · tap the one to point at" : "Arrow · tap two things, or drag")
                Text("Done").fontWeight(.semibold)
            }
            .modifier(PillStyle())
        }
        .buttonStyle(.plain)
        #else
        Text(hasSource ? "Arrow · now click the one to point at · esc to stop" : "Arrow · drag between two things or anywhere, or click two · esc to stop")
            .modifier(PillStyle())
            .allowsHitTesting(false)
        #endif
    }
}

private struct PillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Theme.cardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
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

/// A corner (or an arrow's end) to drag: white with a focus-red edge. Bigger on iPhone for a finger.
private struct ResizeHandle: View {
    let isRound: Bool

    #if os(iOS)
    private static let side: CGFloat = 16
    #else
    private static let side: CGFloat = 9
    #endif

    var body: some View {
        Group {
            if isRound {
                Circle().fill(Color.white).overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1.5))
            } else {
                Rectangle().fill(Color.white).overlay(Rectangle().strokeBorder(Theme.accent, lineWidth: 1.5))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .padding(6)
        .contentShape(Rectangle())
        .accessibilityLabel(isRound ? "Arrow end" : "Resize handle")
    }
}

/// A selected arrow or line: a soft band of focus red along it.
private struct LineSelection: View {
    let node: CanvasNode
    let size: CGSize
    let zoom: CGFloat

    var body: some View {
        let line = node.line
        LineShape(
            start: CGPoint(x: size.width / 2 - line.dx / 2, y: size.height / 2 - line.dy / 2),
            end: CGPoint(x: size.width / 2 + line.dx / 2, y: size.height / 2 + line.dy / 2)
        )
        .stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 10 / zoom, lineCap: .round))
        .allowsHitTesting(false)
    }
}

/// A free arrow while the Arrow tool is dragged on empty board.
private struct DraftArrow: View {
    let start: CGPoint
    let end: CGPoint

    var body: some View {
        ZStack {
            LineShape(start: start, end: end)
                .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: LineNodeView.lineWidth, lineCap: .round))
            EdgeLayer.arrowhead(from: start, to: end, lineWidth: LineNodeView.lineWidth)
                .fill(Color.primary.opacity(0.75))
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
