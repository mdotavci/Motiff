import SwiftUI

/// Point up, base along the bottom.
struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Corners at the middle of each side.
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Five points, one straight up.
struct StarShape: Shape {
    /// How far in the inner corners are, as a share of the outer radius.
    var innerRatio: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = CGSize(width: rect.width / 2, height: rect.height / 2)
        var path = Path()
        for index in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
            let scale = index.isMultiple(of: 2) ? 1 : innerRatio
            let point = CGPoint(x: center.x + cos(angle) * outer.width * scale, y: center.y + sin(angle) * outer.height * scale)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The outline a `ShapeKind` draws in a box. Arrows and lines aren't boxes: see `LineShape`.
struct BoxShape: Shape {
    let kind: ShapeKind
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .rectangle, .arrow, .line: RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        case .ellipse: Ellipse().path(in: rect)
        case .triangle: TriangleShape().path(in: rect)
        case .diamond: DiamondShape().path(in: rect)
        case .star: StarShape().path(in: rect)
        }
    }
}

/// A straight line from `start` to `end`, in the shape's own coordinates.
struct LineShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}
