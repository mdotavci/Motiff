import CoreGraphics

/// Where the Map is looking: the canvas point at the middle of the view, and the zoom.
/// Converts between canvas points and view (screen) points.
struct CanvasCamera: Equatable, Sendable {
    var center: CGPoint
    var zoom: CGFloat

    static let zoomRange: ClosedRange<CGFloat> = 0.1...4
    static let initial = CanvasCamera(center: .zero, zoom: 1)

    init(center: CGPoint, zoom: CGFloat) {
        self.center = center
        self.zoom = Self.clamped(zoom)
    }

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    func screenPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - center.x) * zoom + size.width / 2,
            y: (point.y - center.y) * zoom + size.height / 2
        )
    }

    func canvasPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - size.width / 2) / zoom + center.x,
            y: (point.y - size.height / 2) / zoom + center.y
        )
    }

    /// The part of the canvas the view shows.
    func visibleRect(in size: CGSize) -> CGRect {
        let origin = canvasPoint(.zero, in: size)
        return CGRect(x: origin.x, y: origin.y, width: size.width / zoom, height: size.height / zoom)
    }

    /// Moves the content with the fingers: dragging right shows what's to the left.
    func panned(by screenDelta: CGSize) -> CanvasCamera {
        CanvasCamera(
            center: CGPoint(x: center.x - screenDelta.width / zoom, y: center.y - screenDelta.height / zoom),
            zoom: zoom
        )
    }

    /// Zooms by `factor`, keeping the canvas point under `anchor` (a view point) where it is.
    func zoomed(by factor: CGFloat, anchor: CGPoint, in size: CGSize) -> CanvasCamera {
        let pinned = canvasPoint(anchor, in: size)
        let newZoom = Self.clamped(zoom * factor)
        return CanvasCamera(
            center: CGPoint(
                x: pinned.x - (anchor.x - size.width / 2) / newZoom,
                y: pinned.y - (anchor.y - size.height / 2) / newZoom
            ),
            zoom: newZoom
        )
    }

    /// Shows all of `rect` with some room around it, never zoomed in past 100%.
    static func fitting(_ rect: CGRect, in size: CGSize, padding: CGFloat = 64) -> CanvasCamera {
        guard !rect.isNull, rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else {
            return CanvasCamera(center: rect.isNull ? .zero : CGPoint(x: rect.midX, y: rect.midY), zoom: 1)
        }
        let room = CGSize(width: max(size.width - padding * 2, 1), height: max(size.height - padding * 2, 1))
        let zoom = min(room.width / rect.width, room.height / rect.height, 1)
        return CanvasCamera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: zoom)
    }
}
