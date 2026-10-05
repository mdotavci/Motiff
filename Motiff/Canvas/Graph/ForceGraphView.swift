import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Dots and lines to lay out by force. The Canvas's Graph view and the Canvas Graph in the
/// sidebar both draw one.
struct ForceGraphModel: Equatable, Sendable {
    struct Node: Identifiable, Equatable, Sendable {
        let id: UUID
        let label: String
        /// "#RRGGBB"; nil draws the neutral grey.
        let colorHex: String?
        /// At 100%, in points.
        let radius: CGFloat
        /// Where the layout starts it.
        let seed: CGPoint
        /// Labeled all the time, not only when selected.
        let showsLabel: Bool
    }

    struct Edge: Equatable, Sendable {
        let from: UUID
        let to: UUID
        let dashed: Bool
    }

    var nodes: [Node]
    var edges: [Edge]
}

/// Lays a `ForceGraphModel` out off the main actor, then draws it in one pass. Drag to pan,
/// pinch to zoom; click a dot to select it, double-click to open it.
struct ForceGraphView: View {
    let model: ForceGraphModel
    var selection: Set<UUID> = []
    /// While something is selected or filtered: dots outside this are dimmed.
    var highlighted: Set<UUID>?
    /// A dot (nil: the background), and whether ⇧ was held.
    var onSelect: (UUID?, Bool) -> Void = { _, _ in }
    var onOpen: (UUID) -> Void = { _ in }

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var camera = CanvasCamera.initial
    @State private var size: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var pinchStart: CGFloat?
    @State private var isLaidOut = false

    var body: some View {
        SwiftUI.Canvas { context, size in
            draw(in: &context, size: size)
        }
        .background(Theme.canvasGround)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
            size = newSize
            if isLaidOut { fit() }
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { location in
            onSelect(hit(location), Self.shiftIsDown)
        }
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                if let id = hit(value.location) { onOpen(id) }
            }
        )
        .gesture(pan)
        .simultaneousGesture(pinch)
        .overlay(alignment: .bottomTrailing) {
            Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right", action: fit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: 32, height: 32)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
                .padding(Theme.gutter)
                .help("Fit to the window")
        }
        .task(id: model) { await layOut() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Graph of \(model.nodes.count) nodes and \(model.edges.count) lines")
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let dotScale = min(max(camera.zoom, 0.6), 2).squareRoot()

        for edge in model.edges {
            guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
            var path = Path()
            path.move(to: camera.screenPoint(a, in: size))
            path.addLine(to: camera.screenPoint(b, in: size))
            let lit = highlighted.map { $0.contains(edge.from) && $0.contains(edge.to) } ?? true
            context.stroke(
                path,
                with: .color(.primary.opacity(lit ? 0.3 : 0.08)),
                style: StrokeStyle(lineWidth: 1, dash: edge.dashed ? [4, 4] : [])
            )
        }

        for node in model.nodes {
            guard let position = positions[node.id] else { continue }
            let center = camera.screenPoint(position, in: size)
            let radius = node.radius * dotScale
            let lit = highlighted?.contains(node.id) ?? true
            let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let color = node.colorHex.flatMap(HexColor.init)?.color ?? Theme.neutralIdea
            context.fill(dot, with: .color(color.opacity(lit ? 1 : 0.25)))
            if node.colorHex == nil {
                context.stroke(dot, with: .color(.primary.opacity(lit ? 0.3 : 0.1)), lineWidth: 1)
            }
            let isSelected = selection.contains(node.id)
            if isSelected {
                let ring = Path(ellipseIn: CGRect(x: center.x - radius - 4, y: center.y - radius - 4, width: radius * 2 + 8, height: radius * 2 + 8))
                context.stroke(ring, with: .color(Theme.accent), lineWidth: 2)
            }
            if (node.showsLabel || isSelected) && !node.label.isEmpty {
                let text = context.resolve(
                    Text(node.label)
                        .font(.system(size: 11, weight: node.showsLabel ? .medium : .regular))
                        .foregroundStyle(Color.primary.opacity(lit ? 0.85 : 0.3))
                )
                context.draw(text, at: CGPoint(x: center.x, y: center.y + radius + 10), anchor: .top)
            }
        }
    }

    // MARK: Layout

    private func layOut() async {
        let ids = model.nodes.map(\.id)
        let seeds = model.nodes.map(\.seed)
        let index = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let edges = model.edges.compactMap { edge -> (Int, Int)? in
            guard let a = index[edge.from], let b = index[edge.to] else { return nil }
            return (a, b)
        }
        let points = await Task.detached(priority: .userInitiated) {
            ForceLayout.run(positions: seeds, edges: edges)
        }.value
        guard !Task.isCancelled else { return }
        positions = Dictionary(zip(ids, points), uniquingKeysWith: { first, _ in first })
        if !isLaidOut {
            isLaidOut = true
            fit()
        }
    }

    private func fit() {
        let bounds = positions.values.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        guard !bounds.isNull, size.width > 0 else { return }
        camera = .fitting(bounds.insetBy(dx: -40, dy: -40), in: size, padding: 40)
    }

    /// The dot under a view point, within a few points of its edge.
    private func hit(_ point: CGPoint) -> UUID? {
        let dotScale = min(max(camera.zoom, 0.6), 2).squareRoot()
        var best: (id: UUID, distance: CGFloat)?
        for node in model.nodes {
            guard let position = positions[node.id] else { continue }
            let center = camera.screenPoint(position, in: size)
            let distance = ((center.x - point.x) * (center.x - point.x) + (center.y - point.y) * (center.y - point.y)).squareRoot()
            if distance <= node.radius * dotScale + 6, distance < (best?.distance ?? .infinity) {
                best = (node.id, distance)
            }
        }
        return best?.id
    }

    // MARK: Gestures

    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height
                )
                lastDrag = value.translation
                camera = camera.panned(by: delta)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? camera.zoom
                pinchStart = start
                camera = CanvasCamera(center: camera.center, zoom: start * value.magnification)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private static var shiftIsDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }
}
