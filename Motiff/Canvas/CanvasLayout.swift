import CoreGraphics
import Foundation

/// How big things are on a Canvas at 100% zoom, from the design's anatomy board.
enum CanvasLayout {
    /// Root, sub-idea, and anything deeper.
    static let ideaDiameters: [CGFloat] = [128, 88, 64]

    static let referenceWidth: CGFloat = 176
    static let stripHeight: CGFloat = 6
    static let captionHeight: CGFloat = 36
    static let promptSize = CGSize(width: 196, height: 262)
    static let noteSize = CGSize(width: 224, height: 112)
    static let linkSize = CGSize(width: 224, height: 72)

    /// Below this zoom the Map draws plain colored blocks instead of cards.
    static let blockZoom: CGFloat = 0.45

    /// 0 for a root, 1 for a sub-idea or a loose Idea, 2 for anything deeper.
    static func ideaLevel(isRoot: Bool, depth: Int) -> Int {
        isRoot ? 0 : min(max(depth, 1), ideaDiameters.count - 1)
    }

    /// - Parameters:
    ///   - heightOverWidth: the Reference's media shape, for Reference cards.
    ///   - override: a size the user dragged to; wins when set.
    static func size(
        kind: NodeKind,
        ideaLevel: Int,
        heightOverWidth: CGFloat,
        override: CGSize? = nil,
        text: String = "",
        textSize: TextSize = .medium
    ) -> CGSize {
        if let override { return override }
        switch kind {
        case .idea:
            let diameter = ideaDiameters[min(max(ideaLevel, 0), ideaDiameters.count - 1)]
            return CGSize(width: diameter, height: diameter)
        case .reference:
            let media = (referenceWidth * heightOverWidth).rounded()
            return CGSize(width: referenceWidth, height: stripHeight + media + captionHeight)
        case .prompt:
            return promptSize
        case .note:
            return noteSize
        case .link:
            return linkSize
        case .text:
            return textBox(for: text, size: textSize)
        }
    }

    /// Text nodes wrap at this width.
    static let textMaxWidth: CGFloat = 420

    /// Room for `text` at `size`, estimated from the letter count so it needs no fonts: each line
    /// as wide as its letters up to `textMaxWidth`, then wrapping. Empty text still gets a line.
    static func textBox(for text: String, size: TextSize) -> CGSize {
        let font = CGFloat(size.fontSize)
        let letter = font * 0.56
        let padding: CGFloat = 8
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let longest = lines.map(\.count).max() ?? 0
        let width = min(textMaxWidth, max(font * 4, CGFloat(longest) * letter + padding * 2)).rounded()
        let perLine = max(1, Int((width - padding * 2) / letter))
        let rows = lines.reduce(0) { $0 + max(1, Int((Double($1.count) / Double(perLine)).rounded(.up))) }
        return CGSize(width: width, height: (CGFloat(rows) * font * 1.3 + padding * 2).rounded())
    }

    @MainActor
    static func size(of node: CanvasNode) -> CGSize {
        var override: CGSize?
        if let width = node.width, let height = node.height {
            override = CGSize(width: width, height: height)
        }
        return size(
            kind: node.kind,
            ideaLevel: ideaLevel(isRoot: node.isRoot, depth: node.ideaDepth),
            heightOverWidth: node.reference?.displayAspectRatio ?? 1.25,
            override: override,
            text: node.kind == .text ? node.body ?? "" : "",
            textSize: node.textSize
        )
    }
}

// MARK: - Placing new nodes

extension CanvasLayout {
    /// Room kept between a new node and anything already there.
    static let slotGap: CGFloat = 24
    static let maxRings = 12

    /// Where a new node of `size` goes around a node at `center` whose outline reaches `radius`:
    /// the first free spot on rings around it, starting at `startAngle` (radians, 0 is to the
    /// right) and fanning out to either side, one ring further out when a ring is full.
    /// Nothing already placed moves, so positions the user dragged to stay put.
    static func radialSlot(
        around center: CGPoint,
        radius: CGFloat,
        size: CGSize,
        avoiding occupied: [CGRect],
        startAngle: CGFloat = 0,
        gap: CGFloat = slotGap
    ) -> CGPoint {
        func point(_ distance: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
        }
        let reach = (size.width * size.width + size.height * size.height).squareRoot() / 2
        let firstDistance = radius + gap * 2 + reach
        var distance = firstDistance
        for _ in 0..<maxRings {
            // Half a node apart along the ring, so neighbors can pack in.
            let spacing = (min(size.width, size.height) + gap) / 2
            let steps = max(12, Int((2 * .pi * distance) / spacing))
            let step = 2 * .pi / CGFloat(steps)
            for index in 0..<steps {
                // 0, +1, −1, +2, −2, …
                let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                let angle = startAngle + side * CGFloat((index + 1) / 2) * step
                let candidate = point(distance, angle)
                let room = CGRect(
                    x: candidate.x - size.width / 2 - gap / 2,
                    y: candidate.y - size.height / 2 - gap / 2,
                    width: size.width + gap,
                    height: size.height + gap
                )
                if !occupied.contains(where: { $0.intersects(room) }) {
                    return candidate
                }
            }
            distance += max(size.width, size.height) * 0.75 + gap
        }
        return point(firstDistance, startAngle)
    }
}

// MARK: - Placing loose things

extension CanvasLayout {
    /// `point` if a node of `size` fits there without covering anything, otherwise the nearest
    /// free spot on rings around it.
    static func openSpot(for size: CGSize, near point: CGPoint, avoiding occupied: [CGRect], gap: CGFloat = slotGap) -> CGPoint {
        let room = CGRect(
            x: point.x - size.width / 2 - gap / 2,
            y: point.y - size.height / 2 - gap / 2,
            width: size.width + gap,
            height: size.height + gap
        )
        guard occupied.contains(where: { $0.intersects(room) }) else { return point }
        return radialSlot(around: point, radius: 0, size: size, avoiding: occupied, startAngle: 0, gap: gap)
    }

    /// The top-left corner for things added beside what's already on a board: to the right of it,
    /// level with its top. The origin on an empty board.
    static func besideContent(_ occupied: [CGRect], gap: CGFloat = 120) -> CGPoint {
        guard let first = occupied.first else { return .zero }
        let bounds = occupied.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: bounds.maxX + gap, y: bounds.minY)
    }

    /// Centers for `sizes` laid out in rows of `columns`, left to right from `topLeft`, like a
    /// moodboard: each row as tall as its tallest item, items top-aligned in their row.
    static func gridCenters(for sizes: [CGSize], columns: Int, topLeft: CGPoint, gap: CGFloat = slotGap) -> [CGPoint] {
        let columns = max(columns, 1)
        let cellWidth = (sizes.map(\.width).max() ?? 0) + gap
        var centers: [CGPoint] = []
        var top = topLeft.y
        for rowStart in stride(from: 0, to: sizes.count, by: columns) {
            let row = sizes[rowStart..<min(rowStart + columns, sizes.count)]
            for (column, size) in row.enumerated() {
                let left = topLeft.x + CGFloat(column) * cellWidth
                centers.append(CGPoint(x: left + size.width / 2, y: top + size.height / 2))
            }
            top += (row.map(\.height).max() ?? 0) + gap
        }
        return centers
    }
}
