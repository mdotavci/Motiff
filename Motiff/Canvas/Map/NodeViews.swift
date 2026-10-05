import SwiftUI

/// One node at 100% size. The Map scales and places it.
struct NodeView: View {
    let node: CanvasNode
    let size: CGSize
    /// The Map's zoom, so thumbnails decode at the size they're shown.
    let zoom: CGFloat
    /// Set while the node's text is being typed into on the Map.
    var editor: CanvasController?
    /// GIFs and videos play only while the pointer is over them.
    var isPlaying = false
    /// An arrow's run while its end is being dragged; nil draws the stored one.
    var line: CGVector?

    var body: some View {
        switch node.kind {
        case .idea:
            IdeaNodeView(node: node, diameter: size.width, editor: editor)
        case .text:
            TextNodeView(node: node, editor: editor)
        case .sticky:
            StickyNodeView(node: node, editor: editor)
        case .shape where node.isLine:
            LineNodeView(node: node, size: size, line: line ?? node.line)
        case .shape:
            ShapeNodeView(node: node, editor: editor)
        case .reference where node.isBare:
            BarePictureView(node: node, size: size, zoom: zoom, isPlaying: isPlaying)
        case .reference, .prompt, .note, .link:
            CardView(node: node, size: size, zoom: zoom, editor: editor, isPlaying: isPlaying)
        }
    }
}

/// A circle filled with the Idea's color (its own, or its category's), its title inside.
struct IdeaNodeView: View {
    let node: CanvasNode
    let diameter: CGFloat
    var editor: CanvasController?

    var body: some View {
        let hex = node.effectiveColorHex
        Circle()
            .fill(Palette.fill(hex) ?? Theme.neutralIdea)
            .overlay {
                if hex == nil || Palette.needsOutline(hex) {
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                }
            }
            .overlay {
                Group {
                    if let editor {
                        InlineEditor(controller: editor, nodeID: node.id, prompt: "Name this idea", alignment: .center)
                    } else {
                        Text(node.displayTitle)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                    }
                }
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Palette.text(on: hex, chosen: node.textColorHex))
                .multilineTextAlignment(.center)
                .padding(diameter * 0.14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Idea: \(node.displayTitle)")
    }

    private var fontSize: CGFloat {
        if let size = node.fontSize { return CGFloat(size) }
        switch diameter {
        case 120...: return 15
        case 80...: return 12
        default: return 10
        }
    }
}

/// The card shell: category strip on top, rounded corners, then what the kind shows.
struct CardView: View {
    let node: CanvasNode
    let size: CGSize
    let zoom: CGFloat
    var editor: CanvasController?
    var isPlaying = false

    var body: some View {
        let hex = node.effectiveColorHex
        // A Note with a color is a sticky note: filled with it all over.
        let isSticky = node.kind == .note && hex != nil
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.fill(hex) ?? Color.primary.opacity(0.12))
                .brightness(isSticky ? -0.06 : 0)
                .frame(height: CanvasLayout.stripHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height)
        .background(isSticky ? Palette.fill(hex) ?? Theme.cardSurface : Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .reference:
            if let reference = node.reference {
                ReferenceCardContent(
                    reference: reference, colorHex: node.effectiveColorHex, width: size.width, zoom: zoom, isPlaying: isPlaying
                )
            } else {
                MissingReference()
            }
        case .prompt:
            if let reference = node.reference {
                PromptCardContent(
                    reference: reference, colorHex: node.effectiveColorHex, width: size.width, zoom: zoom,
                    editor: editor, nodeID: node.id
                )
            } else {
                MissingReference()
            }
        case .note:
            Group {
                if let editor {
                    InlineEditor(controller: editor, nodeID: node.id, prompt: "Note", axis: .vertical)
                        .font(.system(size: node.effectiveFontSize))
                        .padding(12)
                } else {
                    NoteCardContent(text: node.body ?? "", fontSize: node.effectiveFontSize)
                }
            }
            .foregroundStyle(Palette.text(on: node.effectiveColorHex, chosen: node.textColorHex))
        case .link:
            LinkCardContent(title: node.displayTitle, url: node.url, iconFilename: node.iconFilename, editor: editor, nodeID: node.id)
        case .idea, .text, .sticky, .shape:
            EmptyView()
        }
    }
}

/// A picture on its own, as on a moodboard: just the image, rounded corners. Its origin and
/// purpose show while the pointer is over it.
struct BarePictureView: View {
    let node: CanvasNode
    let size: CGSize
    let zoom: CGFloat
    var isPlaying = false

    var body: some View {
        Group {
            if let reference = node.reference {
                CardMedia(reference: reference, colorHex: node.effectiveColorHex, pointSize: max(size.width, size.height) * zoom, isPlaying: isPlaying)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if isPlaying { OriginBadge(origin: reference.origin).padding(6) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPlaying, let purpose = reference.purpose { PurposeBadge(purpose: purpose).padding(6) }
                    }
            } else {
                MissingReference()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Picture: \(node.displayTitle)")
    }
}

/// A square sticky note: filled with its color (yellow until it's given one), its text on it.
struct StickyNodeView: View {
    let node: CanvasNode
    var editor: CanvasController?

    /// The color a new sticky gets.
    static let defaultHex = "#F6D77A"

    var body: some View {
        let hex = node.effectiveColorHex ?? Self.defaultHex
        Group {
            if let editor {
                InlineEditor(controller: editor, nodeID: node.id, prompt: "Write on it", axis: .vertical)
            } else {
                Text(NoteCardContent.markdown(node.body ?? ""))
            }
        }
        .font(.system(size: node.effectiveFontSize))
        .foregroundStyle(Palette.text(on: hex, chosen: node.textColorHex))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.fill(hex) ?? .yellow, in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            if Palette.needsOutline(hex) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sticky: \(node.displayTitle)")
    }
}

/// A rectangle, circle, triangle, diamond or star in its color, with its label in the middle.
struct ShapeNodeView: View {
    let node: CanvasNode
    var editor: CanvasController?

    var body: some View {
        let hex = node.effectiveColorHex
        let shape = BoxShape(kind: node.shape)
        shape
            .fill(Palette.fill(hex) ?? Theme.neutralIdea)
            .overlay {
                if node.effectiveStrokeWidth > 0 {
                    shape.stroke(hex.map(Palette.ink) ?? Color.primary.opacity(0.35), lineWidth: node.effectiveStrokeWidth)
                }
            }
            .overlay {
                Group {
                    if let editor {
                        InlineEditor(controller: editor, nodeID: node.id, prompt: "Label", axis: .vertical, alignment: .center)
                    } else if let label = node.body, !label.isEmpty {
                        Text(label)
                            .minimumScaleFactor(0.6)
                    }
                }
                .font(.system(size: node.effectiveFontSize, weight: .medium))
                .foregroundStyle(Palette.text(on: hex, chosen: node.textColorHex))
                .multilineTextAlignment(.center)
                .padding(labelInsets)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(node.shape.label): \(node.body ?? "")")
    }

    /// Keeps the label inside the shape's narrower parts.
    private var labelInsets: EdgeInsets {
        switch node.shape {
        case .triangle: EdgeInsets(top: 40, leading: 24, bottom: 10, trailing: 24)
        case .diamond, .star: EdgeInsets(top: 28, leading: 28, bottom: 28, trailing: 28)
        case .ellipse: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        case .rectangle, .arrow, .line: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        }
    }
}

/// A free arrow or line, drawn from its start to its end inside its box. Only the line itself
/// (and a little room around it) takes clicks.
struct LineNodeView: View {
    let node: CanvasNode
    let size: CGSize
    let line: CGVector

    /// A new arrow's thickness.
    static let lineWidth: CGFloat = 2.5

    var body: some View {
        let start = CGPoint(x: size.width / 2 - line.dx / 2, y: size.height / 2 - line.dy / 2)
        let end = CGPoint(x: size.width / 2 + line.dx / 2, y: size.height / 2 + line.dy / 2)
        let color = node.effectiveColorHex.map(Palette.ink) ?? Color.primary.opacity(0.75)
        let width = CGFloat(node.effectiveStrokeWidth)
        ZStack {
            LineShape(start: start, end: end)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: node.isDashed ? [width * 3, width * 2.5] : []))
            if node.shape == .arrow {
                EdgeLayer.arrowhead(from: start, to: end, lineWidth: width).fill(color)
            }
            if node.hasStartArrow {
                EdgeLayer.arrowhead(from: end, to: start, lineWidth: width).fill(color)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(LineShape(start: start, end: end).stroke(style: StrokeStyle(lineWidth: CanvasLayout.linePadding * 2)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.shape.label)
    }
}

/// Free text on the Canvas: just the letters, no card. Big sizes are bold, for headings.
struct TextNodeView: View {
    let node: CanvasNode
    var editor: CanvasController?

    var body: some View {
        let size = node.effectiveFontSize
        Group {
            if let editor {
                InlineEditor(controller: editor, nodeID: node.id, prompt: "Text", axis: .vertical)
            } else {
                Text(node.body ?? "")
            }
        }
        // Big letters are headings: bold.
        .font(.system(size: size, weight: size >= 32 ? .bold : .regular))
        .foregroundStyle(node.textColorHex.map(Palette.ink) ?? Color.primary)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Text: \(node.displayTitle)")
    }
}

// MARK: - Card contents

/// Media first, origin and purpose in its corners, the caption below.
private struct ReferenceCardContent: View {
    let reference: Reference
    let colorHex: String?
    let width: CGFloat
    let zoom: CGFloat
    var isPlaying = false

    var body: some View {
        let mediaHeight = (width * reference.displayAspectRatio).rounded()
        VStack(alignment: .leading, spacing: 0) {
            CardMedia(reference: reference, colorHex: colorHex, pointSize: max(width, mediaHeight) * zoom, isPlaying: isPlaying)
                .frame(width: width, height: mediaHeight)
                .clipped()
                .overlay(alignment: .topLeading) {
                    OriginBadge(origin: reference.origin).padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if let purpose = reference.purpose {
                        PurposeBadge(purpose: purpose).padding(6)
                    }
                }
            Text(reference.caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Prompt first: a band of media (or the typographic cover), then the prompt in mono.
private struct PromptCardContent: View {
    let reference: Reference
    let colorHex: String?
    let width: CGFloat
    let zoom: CGFloat
    /// Set while the prompt is being written on the board.
    var editor: CanvasController?
    var nodeID = UUID()

    var body: some View {
        let prompt = reference.copyablePrompt ?? ""
        let bandHeight: CGFloat = reference.hasMedia ? 84 : 110
        VStack(alignment: .leading, spacing: 0) {
            CardMedia(reference: reference, colorHex: colorHex, pointSize: width * zoom)
                .frame(width: width, height: bandHeight)
                .clipped()
                .overlay(alignment: .topLeading) {
                    OriginBadge(origin: reference.origin).padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if let purpose = reference.purpose {
                        PurposeBadge(purpose: purpose).padding(6)
                    }
                }
            Group {
                if let editor {
                    InlineEditor(controller: editor, nodeID: nodeID, prompt: "Write the prompt", axis: .vertical)
                } else {
                    Text(prompt)
                        .lineLimit(5)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Spacer(minLength: 0)
            HStack {
                Text(reference.model ?? "Prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Copy Prompt", systemImage: "doc.on.doc") { Pasteboard.copy(reference.promptToCopy ?? prompt) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .disabled(prompt.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
    }
}

/// The Reference's media, or its typographic cover on the card's color.
private struct CardMedia: View {
    let reference: Reference
    let colorHex: String?
    /// Longest side as drawn on screen, in points.
    let pointSize: CGFloat
    var isPlaying = false

    var body: some View {
        if reference.hasMedia, isPlaying, reference.mediaType != .image {
            ReferenceMediaView(reference: reference)
        } else if reference.hasMedia {
            ThumbnailImage(url: reference.mediaURL, pointSize: pointSize)
        } else {
            TypographicCover(text: reference.copyablePrompt ?? "", background: colorHex.flatMap(HexColor.init))
        }
    }
}

private struct NoteCardContent: View {
    let text: String
    var fontSize: Double = 14

    var body: some View {
        Text(Self.markdown(text))
            .font(.system(size: fontSize))
            .padding(12)
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct LinkCardContent: View {
    let title: String
    let url: URL?
    let iconFilename: String?
    var editor: CanvasController?
    let nodeID: UUID

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let iconFilename, !iconFilename.isEmpty {
                    ThumbnailImage(url: MediaStore.url(for: iconFilename), pointSize: 28, contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if let editor {
                        InlineEditor(controller: editor, nodeID: nodeID, prompt: "Title")
                    } else {
                        Text(title).lineLimit(1)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                if let host = url?.host() {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
    }
}

private struct MissingReference: View {
    var body: some View {
        Text("Missing reference")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
    }
}

// MARK: - Typing on the Map

/// A text field in place of a node's text while it's edited. Return or clicking elsewhere
/// keeps the text, Esc puts it back. In a Note, ⌥Return starts a new line.
struct InlineEditor: View {
    @Bindable var controller: CanvasController
    let nodeID: UUID
    let prompt: String
    var axis: Axis = .horizontal
    var alignment: TextAlignment = .leading

    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $controller.editDraft, axis: axis)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onSubmit { controller.finishEditing(nodeID) }
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard !press.modifiers.contains(.option) else { return .ignored }
                controller.finishEditing(nodeID)
                return .handled
            }
            .onKeyPress(.escape) {
                controller.finishEditing(nodeID, commit: false)
                return .handled
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused, !isFocused { controller.finishEditing(nodeID) }
            }
            .task {
                // Focus can't move while the field is still being inserted; wait a beat.
                try? await Task.sleep(for: .milliseconds(50))
                focused = true
            }
    }
}
