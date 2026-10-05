import CoreGraphics
import Foundation
import SwiftData

/// One thing on a board: an Idea circle; a Reference, Prompt, Note or Link card; or Text, a
/// Sticky or a Shape drawn straight on the board.
///
/// "Belongs to" is `parent`, and only `CanvasGraph` changes it. "Relates to" links are
/// `CanvasLink`s in `outgoing` / `incoming`.
@Model
final class CanvasNode {
    var id: UUID = UUID()
    var kindRaw: String = NodeKind.note.rawValue

    // MARK: Geometry, in canvas points

    /// Center of the node.
    var x: Double = 0
    var y: Double = 0
    /// Set only when the user resized a card; nil means the kind's default size.
    var width: Double?
    var height: Double?

    // MARK: Content

    var isRoot: Bool = false
    /// Order among siblings: in the Outline, and for ←/→ in the detail view.
    var sortIndex: Double = 0
    /// Ideas: the idea. Links: the page title. Notes: unused.
    var title: String?
    /// Notes: the markdown text. Ideas: the description.
    var body: String?
    /// Links: the URL.
    var urlString: String?
    /// Links: the favicon, stored in the Media folder.
    var iconFilename: String?
    /// Text: its `TextSize`; nil is medium.
    var textSizeRaw: Int?
    /// Shapes: the `ShapeKind`.
    var shapeRaw: String?
    /// Arrows and lines: from their start to their end, in canvas points. The node's position
    /// is the line's middle.
    var lineDX: Double?
    var lineDY: Double?
    /// Arrows and lines: an arrowhead at the start too.
    var hasStartArrow: Bool = false
    /// Letters' size in canvas points, for anything with words; nil is the kind's own size.
    var fontSize: Double?
    /// Arrows and lines: how thick; shapes: their border (0 for none). Nil is the kind's own.
    var strokeWidth: Double?
    /// Arrows and lines: drawn dashed.
    var isDashed: Bool = false
    /// A picture shown on its own, without the card around it.
    var isBare: Bool = false

    // MARK: Look

    /// "#RRGGBB": an Idea's or a Note's fill, a card's strip. nil follows the category.
    var colorHex: String?
    /// "#RRGGBB" for the words; nil picks black or white for the fill (or the theme's text).
    var textColorHex: String?
    /// "#RRGGBB" for the line to `parent`; nil draws it grey.
    var lineColorHex: String?
    /// An arrowhead on the line to `parent`, pointing at this node.
    var lineHasArrow: Bool = false

    // MARK: Relationships

    var canvas: Canvas?
    /// The shared Reference for `.reference` and `.prompt` cards. Inverse on `Reference.canvasNodes`.
    var reference: Reference?
    /// Inverse on `CanvasCategory.nodes`.
    var category: CanvasCategory?

    @Relationship(deleteRule: .nullify) var parent: CanvasNode?
    @Relationship(deleteRule: .nullify, inverse: \CanvasNode.parent) var children: [CanvasNode] = []
    /// Optional label on the belongs-to edge to `parent`.
    var parentLabel: String?

    @Relationship(deleteRule: .cascade, inverse: \CanvasLink.from) var outgoing: [CanvasLink] = []
    @Relationship(deleteRule: .cascade, inverse: \CanvasLink.to) var incoming: [CanvasLink] = []

    init(kind: NodeKind, x: Double, y: Double) {
        self.kindRaw = kind.rawValue
        self.x = x
        self.y = y
    }
}

extension CanvasNode {
    var kind: NodeKind {
        get { NodeKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var isIdea: Bool { kind == .idea }

    /// The color it's drawn in: its own, or its category's.
    var effectiveColorHex: String? {
        colorHex ?? category?.colorHex
    }

    /// A `.shape` node's shape; rectangle if it's missing.
    var shape: ShapeKind {
        get { shapeRaw.flatMap(ShapeKind.init(rawValue:)) ?? .rectangle }
        set { shapeRaw = newValue.rawValue }
    }

    /// An arrow or a line: drawn from point to point, not in a box.
    var isLine: Bool { kind == .shape && shape.isLine }

    /// For arrows and lines: from start to end.
    var line: CGVector {
        get { CGVector(dx: lineDX ?? 0, dy: lineDY ?? 0) }
        set {
            lineDX = Double(newValue.dx)
            lineDY = Double(newValue.dy)
        }
    }

    var textSize: TextSize {
        get { textSizeRaw.flatMap(TextSize.init(rawValue:)) ?? .medium }
        set {
            textSizeRaw = newValue.rawValue
            fontSize = newValue.fontSize
        }
    }

    /// Whether the node has words whose size can change.
    var hasWords: Bool {
        switch kind {
        case .idea, .note, .text, .sticky: true
        case .shape: !isLine
        case .reference, .prompt, .link: false
        }
    }

    /// The size its letters are drawn at: its own, or its kind's.
    var effectiveFontSize: Double {
        if let fontSize { return fontSize }
        switch kind {
        case .text: return textSize.fontSize
        case .sticky: return 16
        case .shape: return 15
        case .note: return 14
        case .idea: return isRoot ? 15 : ideaDepth <= 1 ? 12 : 10
        case .reference, .prompt, .link: return 13
        }
    }

    /// Arrows' and lines' thickness, or a shape's border.
    var effectiveStrokeWidth: Double {
        strokeWidth ?? (isLine ? 2.5 : 1.5)
    }

    var position: CGPoint {
        get { CGPoint(x: x, y: y) }
        set {
            x = newValue.x
            y = newValue.y
        }
    }

    var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    /// How deep an Idea sits: 0 for a root or a loose Idea, 1 for a sub-idea, 2 and up below.
    /// Circle size follows this.
    var ideaDepth: Int {
        ancestors.filter(\.isIdea).count
    }

    /// Parent, grandparent, and so on up to the top. Stops if it ever meets itself.
    var ancestors: [CanvasNode] {
        var result: [CanvasNode] = []
        var current = parent
        while let node = current, node !== self, result.count < 10_000 {
            result.append(node)
            current = node.parent
        }
        return result
    }

    func isDescendant(of node: CanvasNode) -> Bool {
        ancestors.contains { $0 === node }
    }

    /// Children, then their children, depth first.
    var descendants: [CanvasNode] {
        sortedChildren.flatMap { [$0] + $0.descendants }
    }

    var sortedChildren: [CanvasNode] {
        children.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// One line that names the node in lists, menus and search.
    var displayTitle: String {
        switch kind {
        case .idea:
            return nonEmpty(title) ?? "Untitled idea"
        case .note:
            return nonEmpty(body.map(Self.firstLine)) ?? "Empty note"
        case .text:
            return nonEmpty(body.map(Self.firstLine)) ?? "Empty text"
        case .link:
            return nonEmpty(title) ?? nonEmpty(urlString) ?? "Link"
        case .sticky:
            return nonEmpty(body.map(Self.firstLine)) ?? "Empty sticky"
        case .shape:
            return nonEmpty(body.map(Self.firstLine)) ?? shape.label
        case .reference, .prompt:
            return reference?.caption ?? "Missing reference"
        }
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}
