import SwiftUI

/// The whole Canvas small, with the part on screen outlined. Click or drag in it to look there.
/// ⌥⌘M shows or hides it.
struct Minimap: View {
    let controller: CanvasController

    static let size = CGSize(width: 180, height: 120)

    var body: some View {
        let geometry = MinimapGeometry(content: controller.snapshot.bounds, size: Self.size)
        let visible = controller.camera.visibleRect(in: controller.viewSize)
        let dimmed = controller.highlighted
        SwiftUI.Canvas { context, _ in
            for node in controller.snapshot.nodes {
                let rect = geometry.mini(node.rect)
                let color = node.colorHex.flatMap(HexColor.init)?.color ?? Color.primary.opacity(0.35)
                let lit = dimmed?.contains(node.id) ?? true
                let shape = node.kind == .idea ? Path(ellipseIn: rect) : Path(rect)
                context.fill(shape, with: .color(color.opacity(lit ? 0.9 : 0.25)))
            }
            let view = geometry.mini(visible)
            context.stroke(Path(view), with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in controller.center(on: geometry.canvas(value.location)) }
        )
        .help("Click or drag to look somewhere else (\(ShortcutCatalog.minimap.keys) hides this)")
        .accessibilityLabel("Minimap")
    }
}

/// Maps between canvas points and minimap points. The content plus a margin is fitted, so
/// dragging inside the minimap doesn't move what it maps to.
struct MinimapGeometry {
    let origin: CGPoint
    let scale: CGFloat
    let offset: CGPoint

    init(content: CGRect, size: CGSize) {
        let world = content.isNull ? CGRect(x: -500, y: -500, width: 1000, height: 1000)
            : content.insetBy(dx: -content.width * 0.15 - 200, dy: -content.height * 0.15 - 200)
        scale = min(size.width / world.width, size.height / world.height)
        origin = world.origin
        offset = CGPoint(
            x: (size.width - world.width * scale) / 2,
            y: (size.height - world.height * scale) / 2
        )
    }

    func mini(_ rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - origin.x) * scale + offset.x,
            y: (rect.minY - origin.y) * scale + offset.y,
            width: max(rect.width * scale, 1.5),
            height: max(rect.height * scale, 1.5)
        )
    }

    func canvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale + origin.x, y: (point.y - offset.y) / scale + origin.y)
    }
}
