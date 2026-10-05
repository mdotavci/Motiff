import SwiftUI

/// What a click on the board does. One letter each, as in FigJam.
enum CanvasTool: String, CaseIterable, Identifiable, Sendable {
    case select, hand, sticky, note, text, prompt, image, shape, arrow, idea

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "Select"
        case .hand: "Hand"
        case .sticky: "Sticky"
        case .note: "Note"
        case .text: "Text"
        case .prompt: "Prompt"
        case .image: "Image"
        case .shape: "Shape"
        case .arrow: "Arrow"
        case .idea: "Idea"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
        case .sticky: "note"
        case .note: "note.text"
        case .text: "textformat"
        case .prompt: "text.quote"
        case .image: "photo"
        case .shape: "square.on.circle"
        case .arrow: "arrow.up.right"
        case .idea: "circle"
        }
    }

    /// The key that picks it on the board.
    var key: Character {
        switch self {
        case .select: "v"
        case .hand: "h"
        case .sticky: "s"
        case .note: "n"
        case .text: "t"
        case .prompt: "p"
        case .image: "i"
        case .shape: "r"
        case .arrow: "a"
        case .idea: "o"
        }
    }

    /// What a click makes, for the tools that place one thing where you click.
    var adds: NodeKind? {
        switch self {
        case .sticky: .sticky
        case .note: .note
        case .text: .text
        case .shape: .shape
        case .idea: .idea
        case .select, .hand, .prompt, .image, .arrow: nil
        }
    }

    var help: String {
        switch self {
        case .select: "Select and move (V)"
        case .hand: "Move around the board (H)"
        case .sticky: "Sticky note: click where it goes (S)"
        case .note: "Note: click where it goes, or double-click anywhere (N)"
        case .text: "Text: click where it goes (T)"
        case .prompt: "Prompt: click where it goes, then write it (P)"
        case .image: "Images and videos: click where they go (I)"
        case .shape: "Shape: click where it goes (R)"
        case .arrow: "Arrow: drag from one thing to another, or anywhere (A)"
        case .idea: "Idea: click where it goes (O)"
        }
    }
}

/// The tools along the bottom of the board, in groups: moving around, writing, pictures and
/// shapes, then the Library panel. The chosen tool is drawn inverted. Same look as the other
/// floating panels: no shadow. Scrolls sideways when the window is too narrow for it.
struct ToolBar: View {
    let controller: CanvasController
    /// iPhone: the Image button picks from Photos or Files right away instead of being a tool.
    var pickPhotos: (() -> Void)?
    var pickFiles: (() -> Void)?
    /// iPhone: a Paste button at the end (there's no ⌘V).
    var paste: (([NSItemProvider]) -> Void)?

    private static let groups: [[CanvasTool]] = [
        [.select, .hand],
        [.sticky, .note, .text, .prompt],
        [.image, .shape, .arrow, .idea],
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons
            ScrollView(.horizontal, showsIndicators: false) { buttons }
        }
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private var buttons: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                ForEach(group) { tool in
                    button(for: tool)
                }
            }
            divider
            ToolButton(
                title: "Library",
                systemImage: "square.grid.2x2",
                isOn: controller.showsLibrary,
                help: "Library: drag references onto the board (\(ShortcutCatalog.libraryPanel.keys))",
                action: controller.toggleLibrary
            )
            if let paste {
                PasteButton(supportedContentTypes: CaptureService.acceptedTypes, payloadAction: paste)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.roundedRectangle(radius: 7))
                    .tint(.primary)
                    .padding(.leading, 2)
            }
        }
        .padding(4)
    }

    private var divider: some View {
        Divider().frame(height: 24).padding(.horizontal, 3)
    }

    @ViewBuilder
    private func button(for tool: CanvasTool) -> some View {
        switch tool {
        case .image where pickPhotos != nil:
            Menu {
                Button("Photos and Videos…", systemImage: "photo.on.rectangle") { pickPhotos?() }
                Button("Files…", systemImage: "folder") { pickFiles?() }
            } label: {
                ToolIcon(systemImage: tool.systemImage, isOn: false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(tool.label)
        case .shape:
            HStack(spacing: 0) {
                ToolButton(
                    title: controller.shapeTool.label,
                    systemImage: controller.shapeTool.systemImage,
                    isOn: controller.tool == .shape,
                    help: tool.help
                ) { toggle(.shape) }
                Menu {
                    ForEach(ShapeKind.drawn) { shape in
                        Button(shape.label, systemImage: shape.systemImage) {
                            controller.setShapeTool(shape)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 34)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("Choose a shape")
                .accessibilityLabel("Choose a shape")
            }
        default:
            ToolButton(title: tool.label, systemImage: tool.systemImage, isOn: controller.tool == tool, help: tool.help) {
                toggle(tool)
            }
        }
    }

    /// Clicking the chosen tool again goes back to Select.
    private func toggle(_ tool: CanvasTool) {
        controller.setTool(controller.tool == tool && tool != .select ? .select : tool)
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
            ToolIcon(systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ToolIcon: View {
    let systemImage: String
    let isOn: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .frame(width: 34, height: 34)
            .foregroundStyle(isOn ? Theme.cardSurface : Color.primary)
            .background(isOn ? Color.primary : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
