import SwiftUI

/// The Canvas drawn as a map: lines underneath, Ideas and cards on top, a legend and zoom
/// control floating over it. Drag (or two-finger scroll) pans, pinch zooms around the pointer.
struct CanvasMapView: View {
    let canvas: Canvas

    @State private var controller: CanvasController
    @State private var lastDrag: CGSize = .zero

    init(canvas: Canvas) {
        self.canvas = canvas
        _controller = State(initialValue: CanvasController(canvas: canvas))
    }

    var body: some View {
        let camera = controller.camera
        let size = controller.viewSize
        ZStack(alignment: .topLeading) {
            Theme.canvasGround

            EdgeLayer(snapshot: controller.snapshot, camera: camera)

            ForEach(controller.visibleNodes) { geometry in
                if let node = controller.node(geometry.id) {
                    NodeView(node: node, size: geometry.rect.size, zoom: camera.zoom)
                        .frame(width: geometry.rect.width, height: geometry.rect.height)
                        .scaleEffect(camera.zoom)
                        .position(camera.screenPoint(geometry.center, in: size))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
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
        .overlay(alignment: .topLeading) {
            CategoryLegendBar(canvas: canvas)
                .padding(Theme.gutter)
        }
        .overlay(alignment: .bottomTrailing) {
            ZoomControl(controller: controller)
                .padding(Theme.gutter)
        }
        .onAppear { controller.reload() }
        .onChange(of: canvas.updatedAt) { controller.reload() }
        .focusedSceneValue(\.canvasZoom, CanvasZoomActions(
            zoomIn: controller.zoomIn,
            zoomOut: controller.zoomOut,
            fit: controller.fitToContent
        ))
        .navigationTitle(canvas.displayTitle)
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
