import Foundation
import SwiftData

/// A "relates to" link between two nodes on the same Canvas, drawn dashed.
/// "Belongs to" isn't stored here: it's `CanvasNode.parent`.
@Model
final class CanvasLink {
    var id: UUID = UUID()
    /// A short optional word or two on the line, like "contrast" or "next step".
    var label: String?
    /// "#RRGGBB" for the line; nil draws it grey.
    var colorHex: String?
    /// An arrowhead at the `to` end.
    var hasArrow: Bool = true
    /// An arrowhead at the `from` end too.
    var hasStartArrow: Bool = false
    /// How thick; nil is 2.
    var lineWidth: Double?
    /// Drawn dashed (the default for a link); false draws it solid.
    var isDashed: Bool = true

    var canvas: Canvas?
    /// Inverse on `CanvasNode.outgoing`.
    var from: CanvasNode?
    /// Inverse on `CanvasNode.incoming`.
    var to: CanvasNode?

    init(label: String? = nil) {
        self.label = label
    }
}
