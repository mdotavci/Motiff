import CoreGraphics

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
        override: CGSize? = nil
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
        }
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
            override: override
        )
    }
}
