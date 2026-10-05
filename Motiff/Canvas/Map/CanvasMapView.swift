import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// The Canvas drawn as a map: lines underneath, Ideas and cards on top, a legend and zoom
/// control floating over it. Drag the background (or two-finger scroll) to pan, pinch to zoom
/// around the pointer. Click selects, drag moves, Tab and ⌘Return add, Return edits in place.
struct CanvasMapView: View {
    let canvas: Canvas

    @State private var controller: CanvasController
    @State private var lastDrag: CGSize = .zero
    @FocusState private var mapFocused: Bool
    /// The line whose label is being typed in the Label… alert.
    @State private var labelingEdge: CanvasSnapshot.Edge?
    @State private var labelDraft = ""
    @State private var isImporting = false

    /// The Map's own coordinate space, so node drags measure against something that stays put.
    private static let space = "canvas.map"

    init(canvas: Canvas) {
        self.canvas = canvas
        _controller = State(initialValue: CanvasController(canvas: canvas))
    }

    var body: some View {
        let camera = controller.camera
        let size = controller.viewSize
        let shown = controller.displayedSnapshot
        let dragging = controller.drag?.ids ?? []
        let highlighted = controller.highlighted
        let targetID = controller.connect?.targetID
        ZStack(alignment: .topLeading) {
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
                focus: highlighted == nil ? nil : controller.selection
            )

            ForEach(controller.visibleNodes(in: shown)) { geometry in
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
                        isDimmed: highlighted.map { !$0.contains(node.id) } ?? false
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
        // ⌘V: images, links and prompts go onto the selected Idea (or the root).
        .onPasteCommand(of: CaptureService.acceptedTypes) { providers in
            let target = controller.pasteTargetID
            Task { await controller.capture(providers, at: nil, onto: target) }
        }
        #endif
        .onDrop(of: CaptureService.acceptedTypes, delegate: CanvasDropDelegate(controller: controller))
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            let target = controller.pasteTargetID
            Task { await controller.capture(urls.map { CaptureItem.file($0) }, at: nil, onto: target) }
        }
        .focusable()
        .focused($mapFocused)
        .focusEffectDisabled()
        .onKeyPress(
            keys: [.tab, .return, .delete, .deleteForward, .escape, .space, .leftArrow, .rightArrow, "l"],
            phases: [.down, .repeat]
        ) { press in
            handleKey(press)
        }
        .overlay(alignment: .topLeading) {
            CategoryLegendBar(canvas: canvas)
                .padding(Theme.gutter)
        }
        .overlay(alignment: .bottomTrailing) {
            ZoomControl(controller: controller)
                .padding(Theme.gutter)
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
                        .transition(.hero(from: heroSource(for: item), in: size))
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
                Button("Inspector", systemImage: "sidebar.right", action: controller.toggleInspector)
                    .help("Show Inspector (\(ShortcutCatalog.inspector.keys))")
            }
        }
        .onAppear {
            controller.reload()
            if controller.editingID == nil { mapFocused = true }
            #if DEBUG
            controller.applyLaunchPaste()
            #endif
        }
        .onChange(of: canvas.updatedAt) { controller.reload() }
        .onChange(of: controller.editingID) { _, editing in
            // Back to the Map when typing ends, so Tab and ⌫ work again.
            if editing == nil { mapFocused = true }
        }
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
        .focusedSceneValue(\.canvasZoom, CanvasZoomActions(
            zoomIn: controller.zoomIn,
            zoomOut: controller.zoomOut,
            fit: controller.fitToContent
        ))
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
            copyPrompt: controller.copyPrompt
        ))
        .navigationTitle(canvas.displayTitle)
    }

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
        isDimmed: Bool
    ) -> some View {
        let isEditing = controller.editingID == node.id
        let isSelected = controller.selection.contains(node.id)
        // While typing, clicks and drags belong to the text field.
        let mask: GestureMask = isEditing ? .subviews : .all
        return NodeView(
            node: node,
            size: geometry.rect.size,
            zoom: camera.zoom,
            editor: isEditing ? controller : nil,
            isPlaying: isHovered && controller.drag == nil
        )
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
        guard case let .node(id) = item else { return nil }
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
            } else {
                controller.clearSelection()
            }
        default:
            return .ignored
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

/// The Canvas's categories with how many nodes each has. Filtering arrives with step 7.
private struct CategoryLegendBar: View {
    let canvas: Canvas

    var body: some View {
        let categories = canvas.sortedCategories
        if !categories.isEmpty {
            HStack(spacing: Theme.unit * 1.5) {
                ForEach(categories) { category in
                    HStack(spacing: 6) {
                        Circle().fill(category.color).frame(width: 9, height: 9)
                        Text(category.name)
                        Text("\(category.nodes.count)").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
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
