import SwiftUI
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
        ZStack(alignment: .topLeading) {
            Theme.canvasGround
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.clearSelection()
                    mapFocused = true
                }

            EdgeLayer(snapshot: shown, camera: camera)

            ForEach(controller.visibleNodes(in: shown)) { geometry in
                if let node = controller.node(geometry.id) {
                    placedNode(node, geometry: geometry, camera: camera, size: size, isDragging: dragging.contains(node.id))
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
            case .active(let location): controller.pointer = location
            case .ended: controller.pointer = nil
            }
        }
        .gesture(panGesture)
        #if os(macOS)
        .modifier(ScrollZoomMonitor(controller: controller))
        #endif
        .focusable()
        .focused($mapFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.tab, .return, .delete, .deleteForward, .escape], phases: [.down, .repeat]) { press in
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
        }
        .onChange(of: canvas.updatedAt) { controller.reload() }
        .onChange(of: controller.editingID) { _, editing in
            // Back to the Map when typing ends, so Tab and ⌫ work again.
            if editing == nil { mapFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in controller.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in controller.reload() }
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
            toggleInspector: controller.toggleInspector
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
        isDragging: Bool
    ) -> some View {
        let isEditing = controller.editingID == node.id
        let isSelected = controller.selection.contains(node.id)
        // While typing, clicks and drags belong to the text field.
        let mask: GestureMask = isEditing ? .subviews : .all
        return NodeView(node: node, size: geometry.rect.size, zoom: camera.zoom, editor: isEditing ? controller : nil)
            .frame(width: geometry.rect.width, height: geometry.rect.height)
            .overlay {
                if isSelected {
                    SelectionRing(isIdea: node.isIdea, zoom: camera.zoom)
                }
            }
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
        case .escape:
            controller.clearSelection()
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
