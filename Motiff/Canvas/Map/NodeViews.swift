import SwiftUI

/// One node at 100% size. The Map scales and places it.
struct NodeView: View {
    let node: CanvasNode
    let size: CGSize
    /// The Map's zoom, so thumbnails decode at the size they're shown.
    let zoom: CGFloat

    var body: some View {
        if node.isIdea {
            IdeaNodeView(node: node, diameter: size.width)
        } else {
            CardView(node: node, size: size, zoom: zoom)
        }
    }
}

/// A circle filled with the Idea's category color, its title inside.
struct IdeaNodeView: View {
    let node: CanvasNode
    let diameter: CGFloat

    var body: some View {
        let hex = node.category?.hexColor
        Circle()
            .fill(hex?.color ?? Theme.neutralIdea)
            .overlay {
                if hex == nil {
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                }
            }
            .overlay {
                Text(node.displayTitle)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(hex?.textColor ?? Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .padding(diameter * 0.14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Idea: \(node.displayTitle)")
    }

    private var fontSize: CGFloat {
        switch diameter {
        case 120...: 15
        case 80...: 12
        default: 10
        }
    }
}

/// The card shell: category strip on top, rounded corners, then what the kind shows.
struct CardView: View {
    let node: CanvasNode
    let size: CGSize
    let zoom: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(node.category?.color ?? Color.primary.opacity(0.12))
                .frame(height: CanvasLayout.stripHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.cardSurface)
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
                ReferenceCardContent(reference: reference, category: node.category, width: size.width, zoom: zoom)
            } else {
                MissingReference()
            }
        case .prompt:
            if let reference = node.reference {
                PromptCardContent(reference: reference, category: node.category, width: size.width, zoom: zoom)
            } else {
                MissingReference()
            }
        case .note:
            NoteCardContent(text: node.body ?? "")
        case .link:
            LinkCardContent(title: node.displayTitle, url: node.url)
        case .idea:
            EmptyView()
        }
    }
}

// MARK: - Card contents

/// Media first, origin and purpose in its corners, the caption below.
private struct ReferenceCardContent: View {
    let reference: Reference
    let category: CanvasCategory?
    let width: CGFloat
    let zoom: CGFloat

    var body: some View {
        let mediaHeight = (width * reference.displayAspectRatio).rounded()
        VStack(alignment: .leading, spacing: 0) {
            CardMedia(reference: reference, category: category, pointSize: max(width, mediaHeight) * zoom)
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
    let category: CanvasCategory?
    let width: CGFloat
    let zoom: CGFloat

    var body: some View {
        let prompt = reference.copyablePrompt ?? ""
        let bandHeight: CGFloat = reference.hasMedia ? 84 : 110
        VStack(alignment: .leading, spacing: 0) {
            CardMedia(reference: reference, category: category, pointSize: width * zoom)
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
            Text(prompt)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(5)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            Spacer(minLength: 0)
            HStack {
                Text(reference.model ?? "Prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Copy Prompt", systemImage: "doc.on.doc") { Pasteboard.copy(prompt) }
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

/// The Reference's media, or its typographic cover on the card's category color.
private struct CardMedia: View {
    let reference: Reference
    let category: CanvasCategory?
    /// Longest side as drawn on screen, in points.
    let pointSize: CGFloat

    var body: some View {
        if reference.hasMedia {
            ThumbnailImage(url: reference.mediaURL, pointSize: pointSize)
        } else {
            TypographicCover(text: reference.copyablePrompt ?? "", background: category?.hexColor)
        }
    }
}

private struct NoteCardContent: View {
    let text: String

    var body: some View {
        Text(Self.markdown(text))
            .font(.system(size: 14))
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
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
