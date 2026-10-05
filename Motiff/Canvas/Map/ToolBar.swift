import SwiftUI

/// What a click on the Map does. One letter each, as in FigJam.
enum CanvasTool: String, CaseIterable, Identifiable, Sendable {
    case select, hand, idea, note, text, image, link

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .hand: "Hand"
        case .idea: "Idea"
        case .note: "Note"
        case .text: "Text"
        case .image: "Image"
        case .link: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
        case .idea: "circle"
        case .note: "note.text"
        case .text: "textformat"
        case .image: "photo"
        case .link: "arrow.up.right"
        }
    }

    /// The key that picks it on the Map.
    var key: Character {
        switch self {
        case .select: "v"
        case .hand: "h"
        case .idea: "o"
        case .note: "n"
        case .text: "t"
        case .image: "i"
        case .link: "l"
        }
    }

    /// What the click makes, for the adding tools.
    var adds: NodeKind? {
        switch self {
        case .idea: .idea
        case .note: .note
        case .text: .text
        case .select, .hand, .image, .link: nil
        }
    }

    var help: String {
        switch self {
        case .select: "Select and move (V)"
        case .hand: "Move around the board (H)"
        case .idea: "Idea: click where it goes (O)"
        case .note: "Note: click where it goes, or double-click anywhere (N)"
        case .text: "Text: click where it goes (T)"
        case .image: "Images and videos: click where they go (I)"
        case .link: "Link two nodes: click one, then the other (L)"
        }
    }
}

/// The tools down the left side of the Map, and the Library panel's button at the bottom.
/// The chosen tool is drawn inverted. Same look as the other floating panels: no shadow.
struct ToolBar: View {
    let controller: CanvasController

    var body: some View {
        VStack(spacing: 2) {
            ForEach(CanvasTool.allCases) { tool in
                ToolButton(
                    title: tool.label,
                    systemImage: tool.systemImage,
                    isOn: controller.tool == tool,
                    help: tool.help
                ) {
                    controller.setTool(controller.tool == tool && tool != .select ? .select : tool)
                }
                if tool == .hand || tool == .image {
                    Divider().frame(width: 24).padding(.vertical, 3)
                }
            }
            Divider().frame(width: 24).padding(.vertical, 3)
            ToolButton(
                title: "Library",
                systemImage: "square.grid.2x2",
                isOn: controller.showsLibrary,
                help: "Library: drag references onto the board (\(ShortcutCatalog.libraryPanel.keys))",
                action: controller.toggleLibrary
            )
        }
        .padding(4)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .frame(width: 34, height: 34)
                .foregroundStyle(isOn ? Theme.cardSurface : Color.primary)
                .background(isOn ? Color.primary : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
