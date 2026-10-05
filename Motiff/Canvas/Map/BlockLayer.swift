import SwiftUI

/// Far out (below `CanvasLayout.blockZoom`), every node drawn in one pass instead of as views:
/// cards as blocks in their category color, Ideas as flat circles, titles once there's room.
/// No thumbnails, so a Canvas of hundreds of nodes stays smooth.
struct BlockLayer: View {
    let nodes: [CanvasSnapshot.Node]
    let camera: CanvasCamera
    /// While something is selected or filtered: nodes outside this are dimmed.
    var highlighted: Set<UUID>?

    /// Narrower than this on screen, a block gets no title.
    static let titleMinimumWidth: CGFloat = 54

    var body: some View {
        SwiftUI.Canvas { context, size in
            for node in nodes {
                let origin = camera.screenPoint(node.rect.origin, in: size)
                let rect = CGRect(origin: origin, size: CGSize(width: node.rect.width * camera.zoom, height: node.rect.height * camera.zoom))
                let hex = node.colorHex.flatMap(HexColor.init)
                var layer = context
                if let highlighted, !highlighted.contains(node.id) { layer.opacity = 0.3 }

                if node.kind == .idea {
                    let circle = Path(ellipseIn: rect)
                    layer.fill(circle, with: .color(hex?.color ?? Theme.neutralIdea))
                } else {
                    let block = Path(roundedRect: rect, cornerRadius: max(Theme.cardCorner * camera.zoom, 2))
                    if let hex {
                        layer.fill(block, with: .color(hex.color.opacity(0.85)))
                    } else {
                        layer.fill(block, with: .color(Theme.cardSurface))
                        layer.stroke(block, with: .color(Theme.cardBorder), lineWidth: 1)
                    }
                }

                if rect.width >= Self.titleMinimumWidth, !node.title.isEmpty {
                    let ink = hex?.textColor ?? Color.primary
                    let text = layer.resolve(
                        Text(node.title)
                            .font(.system(size: node.kind == .idea ? 11 : 10, weight: node.kind == .idea ? .semibold : .regular))
                            .foregroundStyle(ink)
                    )
                    let inset = rect.insetBy(dx: min(6, rect.width / 6), dy: min(4, rect.height / 6))
                    if node.kind == .idea {
                        layer.draw(text, in: inset.insetBy(dx: inset.width * 0.1, dy: inset.height * 0.3))
                    } else {
                        layer.draw(text, in: inset)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
