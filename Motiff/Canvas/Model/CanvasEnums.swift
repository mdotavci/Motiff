import Foundation

/// What a node on a Canvas is. Ideas are circles; everything else is a card.
enum NodeKind: String, Codable, CaseIterable {
    /// A circle. The first one in a Canvas is its root.
    case idea
    /// A Reference shown media first.
    case reference
    /// A Reference shown prompt first: the prompt text is the card, the media a band on top.
    case prompt
    /// Markdown text, no media.
    case note
    /// A URL with its title and favicon.
    case link
    /// Free text straight on the Canvas, no card around it: headings, labels, comments.
    case text

    var label: String {
        switch self {
        case .idea: "Idea"
        case .reference: "Reference"
        case .prompt: "Prompt"
        case .note: "Note"
        case .link: "Link"
        case .text: "Text"
        }
    }
}

/// How big a Text node's letters are.
enum TextSize: Int, CaseIterable, Identifiable, Sendable {
    case small, medium, large, huge

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

    /// In canvas points at 100% zoom.
    var fontSize: Double {
        switch self {
        case .small: 14
        case .medium: 20
        case .large: 32
        case .huge: 48
        }
    }

    var isBold: Bool { self == .large || self == .huge }
}

/// The two kinds of edge on a Canvas.
///
/// Only "relates to" is stored as a `CanvasLink`. "Belongs to" is `CanvasNode.parent`, so the
/// hierarchy and its edges can never disagree.
enum LinkType: String, Codable, CaseIterable {
    /// Solid thin line: a card and its Idea, or a sub-idea and its Idea.
    case belongsTo
    /// Dashed thicker line: any cross-link.
    case relatesTo

    var label: String {
        switch self {
        case .belongsTo: "Belongs to"
        case .relatesTo: "Relates to"
        }
    }
}

/// Where a Canvas was last looked at: the canvas point at the center of the window, and the zoom.
struct CanvasViewport: Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var zoom: Double

    static let initial = CanvasViewport(centerX: 0, centerY: 0, zoom: 1)
}

/// The three ways to look at a Canvas.
enum CanvasViewMode: String, CaseIterable, Identifiable, Sendable {
    /// Ideas and cards where you put them.
    case map
    /// An indented list, for reordering and restructuring from the keyboard.
    case outline
    /// Dots and lines laid out by force, to see the shape of it.
    case graph

    var id: String { rawValue }

    var label: String {
        switch self {
        case .map: "Map"
        case .outline: "Outline"
        case .graph: "Graph"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "rectangle.3.group"
        case .outline: "list.bullet.indent"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }
}
