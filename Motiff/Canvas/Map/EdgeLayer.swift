import SwiftUI

/// Every line on the Map, drawn in one pass: belongs-to solid and thin, relates-to dashed and
/// thicker, in their own color if they have one, with an arrowhead if they have one, labels in
/// a pill at the middle. Line widths stay the same at every zoom.
struct EdgeLayer: View {
    let snapshot: CanvasSnapshot
    let camera: CanvasCamera
    /// The line under the pointer, drawn heavier.
    var hoveredEdgeID: String?
    /// The selected line, drawn heavier in focus red.
    var selectedEdgeID: String?
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
                let selected = edge.id == selectedEdgeID
                let hovered = edge.id == hoveredEdgeID || selected
                let dimmed = focus.map { !$0.contains(edge.from) && !$0.contains(edge.to) } ?? false

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                var lineContext = context
                if dimmed { lineContext.opacity = 0.3 }
                let color = lineColor(of: edge, hovered: hovered, selected: selected)
                let width: CGFloat = switch edge.type {
                case .belongsTo: hovered ? 2.5 : (edge.colorHex == nil ? 1 : 1.5)
                case .relatesTo: hovered ? 3.5 : 2
                }
                lineContext.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, dash: edge.type == .relatesTo ? [6, 5] : [])
                )
                if edge.hasArrow {
                    lineContext.fill(Self.arrowhead(from: start, to: end, lineWidth: width), with: .color(color))
                }

                if let label = edge.label, !label.isEmpty, camera.zoom >= Self.labelMinimumZoom {
                    drawLabel(label, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), in: &lineContext)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Grey as before when it has no color; its color's ink when it has one; red when selected.
    private func lineColor(of edge: CanvasSnapshot.Edge, hovered: Bool, selected: Bool) -> Color {
        if selected { return Theme.accent }
        if let hex = edge.colorHex { return Palette.ink(hex) }
        switch edge.type {
        case .belongsTo: return .primary.opacity(hovered ? 0.7 : 0.3)
        case .relatesTo: return .primary.opacity(hovered ? 0.8 : 0.45)
        }
    }

    /// A filled triangle at `end`, pointing along the line, sized to the line's width.
    static func arrowhead(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = 8 + lineWidth * 2
        let spread = CGFloat.pi / 7
        var path = Path()
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
        path.addLine(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
        path.closeSubpath()
        return path
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
