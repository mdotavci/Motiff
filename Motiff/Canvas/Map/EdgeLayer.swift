import SwiftUI

/// Every line on the Map, drawn in one pass: belongs-to solid and thin, relates-to dashed and
/// thicker, labels in a pill at the middle. Line widths stay the same at every zoom.
struct EdgeLayer: View {
    let snapshot: CanvasSnapshot
    let camera: CanvasCamera
    /// The line under the pointer, drawn heavier.
    var hoveredEdgeID: String?
    /// While something is selected: lines that touch none of it are dimmed.
    var focus: Set<UUID>?

    /// Below this zoom, labels are too small to read and are left out.
    static let labelMinimumZoom: CGFloat = 0.4

    var body: some View {
        SwiftUI.Canvas { context, size in
            for edge in snapshot.edges {
                guard let segment = snapshot.segment(of: edge) else { continue }
                let start = camera.screenPoint(segment.start, in: size)
                let end = camera.screenPoint(segment.end, in: size)
                let hovered = edge.id == hoveredEdgeID
                let dimmed = focus.map { !$0.contains(edge.from) && !$0.contains(edge.to) } ?? false

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                var lineContext = context
                if dimmed { lineContext.opacity = 0.3 }
                switch edge.type {
                case .belongsTo:
                    lineContext.stroke(
                        path,
                        with: .color(.primary.opacity(hovered ? 0.7 : 0.3)),
                        lineWidth: hovered ? 2.5 : 1
                    )
                case .relatesTo:
                    lineContext.stroke(
                        path,
                        with: .color(.primary.opacity(hovered ? 0.8 : 0.45)),
                        style: StrokeStyle(lineWidth: hovered ? 3.5 : 2, dash: [6, 5])
                    )
                }

                if let label = edge.label, !label.isEmpty, camera.zoom >= Self.labelMinimumZoom {
                    drawLabel(label, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), in: &lineContext)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawLabel(_ label: String, at point: CGPoint, in context: inout GraphicsContext) {
        let text = context.resolve(Text(label).font(.system(size: 11)).foregroundStyle(.secondary))
        let textSize = text.measure(in: CGSize(width: 240, height: 40))
        let pill = CGRect(
            x: point.x - textSize.width / 2 - 8,
            y: point.y - textSize.height / 2 - 3,
            width: textSize.width + 16,
            height: textSize.height + 6
        )
        let shape = Path(roundedRect: pill, cornerRadius: pill.height / 2)
        context.fill(shape, with: .color(Theme.canvasGround))
        context.stroke(shape, with: .color(.primary.opacity(0.15)), lineWidth: 1)
        context.draw(text, at: point)
    }
}
