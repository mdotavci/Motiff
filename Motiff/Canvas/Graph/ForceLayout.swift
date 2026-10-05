import CoreGraphics
import Foundation

/// Fruchterman–Reingold: every pair of nodes pushes apart, every line pulls its ends together,
/// and the moves shrink as the layout cools. Started from the Map's positions, so the Graph
/// keeps the Map's rough arrangement. Pure and synchronous; callers run it off the main actor.
enum ForceLayout {
    /// - Parameters:
    ///   - positions: where each node starts.
    ///   - edges: pairs of indexes into `positions`.
    ///   - distance: the spacing the layout settles toward.
    static func run(
        positions: [CGPoint],
        edges: [(Int, Int)],
        distance k: CGFloat = 90,
        iterations: Int = 250
    ) -> [CGPoint] {
        let count = positions.count
        guard count > 1 else { return positions }
        var points = positions
        var temperature = k * 2
        let cooling = temperature / CGFloat(max(iterations, 1))

        for _ in 0..<iterations {
            var moves = Array(repeating: CGPoint.zero, count: count)

            for i in 0..<count {
                for j in (i + 1)..<count {
                    var dx = points[i].x - points[j].x
                    var dy = points[i].y - points[j].y
                    if dx * dx + dy * dy < 0.0001 {
                        // Two nodes on the same spot: nudge them apart the same way every time.
                        dx = CGFloat((i % 7) - 3) * 0.1 + 0.05
                        dy = CGFloat((j % 5) - 2) * 0.1 + 0.05
                    }
                    let length = (dx * dx + dy * dy).squareRoot()
                    let push = k * k / length
                    let fx = dx / length * push
                    let fy = dy / length * push
                    moves[i].x += fx
                    moves[i].y += fy
                    moves[j].x -= fx
                    moves[j].y -= fy
                }
            }

            for (a, b) in edges where a != b && points.indices.contains(a) && points.indices.contains(b) {
                let dx = points[a].x - points[b].x
                let dy = points[a].y - points[b].y
                let length = max((dx * dx + dy * dy).squareRoot(), 0.01)
                let pull = length * length / k
                let fx = dx / length * pull
                let fy = dy / length * pull
                moves[a].x -= fx
                moves[a].y -= fy
                moves[b].x += fx
                moves[b].y += fy
            }

            // A little gravity, so pieces that aren't connected don't drift off.
            let center = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(count),
                y: points.map(\.y).reduce(0, +) / CGFloat(count)
            )
            for i in 0..<count {
                moves[i].x -= (points[i].x - center.x) * 0.05
                moves[i].y -= (points[i].y - center.y) * 0.05
                let length = (moves[i].x * moves[i].x + moves[i].y * moves[i].y).squareRoot()
                guard length > 0, length.isFinite else { continue }
                let step = min(length, temperature)
                points[i].x += moves[i].x / length * step
                points[i].y += moves[i].y / length * step
            }
            temperature = max(temperature - cooling, 0.5)
        }
        return points
    }
}
