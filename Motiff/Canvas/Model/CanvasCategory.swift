import Foundation
import SwiftData

/// A user-named color for classifying nodes on one Canvas: the strip on top of a card, the fill
/// of an Idea circle, and a filter in the legend.
@Model
final class CanvasCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// "#RRGGBB", always one of `CanvasCategory.swatches`.
    var colorHex: String = ""
    /// Position in the legend.
    var order: Int = 0

    var canvas: Canvas?
    @Relationship(deleteRule: .nullify, inverse: \CanvasNode.category) var nodes: [CanvasNode] = []

    init(name: String, colorHex: String, order: Int) {
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }
}

extension CanvasCategory {
    struct Swatch: Hashable, Sendable {
        let name: String
        let hex: String
    }

    /// A name and a color, before it becomes a category on a Canvas.
    struct Preset: Hashable, Sendable {
        let name: String
        let hex: String
    }

    /// The only colors a category can have. There's no free picker, so none of them can land
    /// on the focus red (`Theme.accent`), and each reads on dark and light grounds.
    static let swatches: [Swatch] = [
        Swatch(name: "Amber", hex: "#C58A2C"),
        Swatch(name: "Blue", hex: "#4C63D2"),
        Swatch(name: "Rust", hex: "#C4733F"),
        Swatch(name: "Teal", hex: "#287F75"),
        Swatch(name: "Violet", hex: "#8761C8"),
        Swatch(name: "Olive", hex: "#7F8C3C"),
        Swatch(name: "Slate", hex: "#6B7A8F"),
        Swatch(name: "Sand", hex: "#B59A6B"),
        Swatch(name: "Moss", hex: "#4E7D4F"),
        Swatch(name: "Plum", hex: "#8E5A8A"),
    ]

    /// What every new Canvas starts with. Names are editable.
    static let defaults: [Preset] = [
        Preset(name: "Typography", hex: "#C58A2C"),
        Preset(name: "Reference", hex: "#4C63D2"),
        Preset(name: "To try", hex: "#C4733F"),
        Preset(name: "Color", hex: "#287F75"),
        Preset(name: "Mood", hex: "#8761C8"),
        Preset(name: "Process", hex: "#7F8C3C"),
    ]
}
