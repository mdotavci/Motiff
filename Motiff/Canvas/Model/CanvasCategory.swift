import Foundation
import SwiftData

/// A user-named color for classifying nodes on one Canvas: the strip on top of a card, the fill
/// of an Idea circle, and a filter in the legend.
@Model
final class CanvasCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// "#RRGGBB": one of `CanvasCategory.swatches`, or a custom color.
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
    /// One color of the palette: a pastel `hex` to fill with, and a deeper `ink` of the same
    /// hue for lines and words on a light ground. On a dark ground lines use `darkLine`.
    struct Swatch: Hashable, Sendable {
        let name: String
        let hex: String
        let ink: String
        var darkLine: String?

        /// What lines and words in this color are drawn with on a dark ground.
        var onDark: String { darkLine ?? hex }
    }

    /// A name and a color, before it becomes a category on a Canvas.
    struct Preset: Hashable, Sendable {
        let name: String
        let hex: String
    }

    /// The palette: soft pastels with dark words on them, each with an ink for lines and text.
    /// Black words read at least 4.5:1 on every fill, every ink at least 4.5:1 on the light
    /// ground, every fill (or dark line) at least 3:1 on the dark one. No red: that's focus.
    static let swatches: [Swatch] = [
        Swatch(name: "Yellow", hex: "#F6D77A", ink: "#86670A"),
        Swatch(name: "Orange", hex: "#F7B98A", ink: "#A4531A"),
        Swatch(name: "Pink", hex: "#F3B2C6", ink: "#AE3A70"),
        Swatch(name: "Purple", hex: "#C7B3F0", ink: "#7448CC"),
        Swatch(name: "Lavender", hex: "#DCCFF7", ink: "#6A55B4"),
        Swatch(name: "Blue", hex: "#9CC4F2", ink: "#1C69C2"),
        Swatch(name: "Sky", hex: "#BFE3F5", ink: "#19709A"),
        Swatch(name: "Teal", hex: "#8FD6CF", ink: "#277770"),
        Swatch(name: "Mint", hex: "#BDEBD8", ink: "#227754"),
        Swatch(name: "Green", hex: "#9ED9A8", ink: "#2A7638"),
        Swatch(name: "Lime", hex: "#CFE59A", ink: "#5A741C"),
        Swatch(name: "Sand", hex: "#E6D3A8", ink: "#846624"),
        Swatch(name: "Brown", hex: "#D4B8A0", ink: "#8E603A"),
        Swatch(name: "Grey", hex: "#D9D9DE", ink: "#636369"),
        Swatch(name: "White", hex: "#FFFFFF", ink: "#6A6A70"),
        Swatch(name: "Charcoal", hex: "#4A4A4F", ink: "#3A3A3E", darkLine: "#B8B8BE"),
    ]

    static func swatch(for hex: String?) -> Swatch? {
        guard let hex else { return nil }
        return swatches.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    /// What every new Canvas starts with. Names are editable.
    static let defaults: [Preset] = [
        Preset(name: "Typography", hex: "#F6D77A"),
        Preset(name: "Reference", hex: "#9CC4F2"),
        Preset(name: "To try", hex: "#F7B98A"),
        Preset(name: "Color", hex: "#8FD6CF"),
        Preset(name: "Mood", hex: "#C7B3F0"),
        Preset(name: "Process", hex: "#9ED9A8"),
    ]

    /// The first palette's colors and the pastel each became.
    static let legacyColors: [String: String] = [
        "#C58A2C": "#F6D77A", // Amber → Yellow
        "#4C63D2": "#9CC4F2", // Blue
        "#C4733F": "#F7B98A", // Rust → Orange
        "#287F75": "#8FD6CF", // Teal
        "#8761C8": "#C7B3F0", // Violet → Purple
        "#7F8C3C": "#CFE59A", // Olive → Lime
        "#6B7A8F": "#D9D9DE", // Slate → Grey
        "#B59A6B": "#E6D3A8", // Sand
        "#4E7D4F": "#9ED9A8", // Moss → Green
        "#8E5A8A": "#F3B2C6", // Plum → Pink
    ]

    /// True for colors too close to the focus red (`Theme.accent`, #E2231A) to use: red means
    /// selected, so nothing else may look like it.
    static func isFocusRed(_ hex: String) -> Bool {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return false }
        let red = (value >> 16) & 0xFF, green = (value >> 8) & 0xFF, blue = value & 0xFF
        let distance = Double((red - 0xE2) * (red - 0xE2) + (green - 0x23) * (green - 0x23) + (blue - 0x1A) * (blue - 0x1A))
        return distance.squareRoot() < 70
    }

    /// "#RRGGBB" in capitals, or nil if it isn't one.
    static func normalized(_ hex: String) -> String? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, Int(digits, radix: 16) != nil else { return nil }
        return "#" + digits.uppercased()
    }
}
