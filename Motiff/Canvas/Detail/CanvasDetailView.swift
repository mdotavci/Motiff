import SwiftUI

/// A node full size over the Map: a Reference or Prompt in the shared Reference detail, an Idea
/// with its description and everything attached to it. Esc goes back, ← → step through the
/// node's siblings. The Map stays underneath, untouched, so going back finds it as it was.
struct CanvasDetailView: View {
    let controller: CanvasController
    let item: CanvasController.DetailItem

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(controller: controller)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Fills the Map even while its content is still loading, so nothing shows through.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .environment(\.openReference, OpenReferenceAction { [controller] reference in
            controller.openDetail(reference: reference)
        })
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .reference(let reference):
            ReferenceDetailContent(reference: reference) { EmptyView() }
        case .node(let id):
            if let node = controller.node(id) {
                switch node.kind {
                case .reference, .prompt:
                    if let reference = node.reference {
                        ReferenceDetailContent(reference: reference) {
                            ConnectionList(node: node, showsChildren: true) { other in
                                controller.openDetail(other.id)
                            }
                        }
                        .id(node.id)
                    } else {
                        EmptyState(title: node.kind.label, message: "This card's Reference was deleted.")
                    }
                case .idea, .note, .link, .text:
                    IdeaDetailView(node: node, controller: controller)
                        .id(node.id)
                }
            }
        }
    }
}

/// Back on the left; where this node sits among its siblings, ← →, and Copy Prompt on the right.
private struct DetailHeader: View {
    let controller: CanvasController

    var body: some View {
        HStack(spacing: Theme.unit) {
            Button {
                withAnimation(.snappy) { controller.closeDetail() }
            } label: {
                Label(controller.detailPath.count > 1 ? "Back" : "Canvas", systemImage: "chevron.left")
            }
            .help("Back (\(ShortcutCatalog.closeDetail.keys))")

            Spacer()

            if controller.promptToCopy != nil {
                Button("Copy Prompt", systemImage: "doc.on.doc", action: controller.copyPrompt)
                    .help("Copy the prompt (\(ShortcutCatalog.copyPrompt.keys))")
            }

            if let position = controller.detailPosition, position.siblings.count > 1 {
                Text(verbatim: "\(position.index + 1) of \(position.siblings.count)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Previous", systemImage: "chevron.left") { controller.stepDetail(by: -1) }
                    .labelStyle(.iconOnly)
                    .disabled(position.index == 0)
                    .help("Previous (\(ShortcutCatalog.previousSibling.keys))")
                Button("Next", systemImage: "chevron.right") { controller.stepDetail(by: 1) }
                    .labelStyle(.iconOnly)
                    .disabled(position.index == position.siblings.count - 1)
                    .help("Next (\(ShortcutCatalog.nextSibling.keys))")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.gutter)
        .frame(height: 44)
    }
}

// MARK: - Ideas, notes and links

/// An Idea's title and description, what it's in, and everything attached to it as a grid.
/// Notes and Links get the same page, with their text or URL.
private struct IdeaDetailView: View {
    let node: CanvasNode
    let controller: CanvasController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.unit * 3) {
                VStack(alignment: .leading, spacing: Theme.unit) {
                    HStack(spacing: 6) {
                        if let category = node.category {
                            Circle().fill(category.color).frame(width: 10, height: 10)
                            Text("\(node.kind.label) · \(category.name)").motiffLabel()
                        } else {
                            Text(node.kind.label).motiffLabel()
                        }
                    }
                    Text(node.displayTitle)
                        .font(.system(size: 28, weight: .semibold))
                        .textSelection(.enabled)
                }

                text

                let children = node.sortedChildren
                if !children.isEmpty {
                    DetailSection("Attached · \(children.count)") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Theme.unit * 1.5)],
                            alignment: .leading,
                            spacing: Theme.unit * 1.5
                        ) {
                            ForEach(children) { child in
                                Button { controller.openDetail(child.id) } label: {
                                    AttachedTile(node: child)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                ConnectionList(node: node) { other in
                    controller.openDetail(other.id)
                }
            }
            .padding(Theme.gutter * 2)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var text: some View {
        switch node.kind {
        case .idea:
            if let description = node.body, !description.isEmpty {
                Text(Self.markdown(description))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
            } else {
                Text("No description yet. Add one in the inspector (\(ShortcutCatalog.inspector.keys)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .note, .text:
            Text(Self.markdown(node.body ?? ""))
                .font(.title3)
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
        case .link:
            if let url = node.url {
                Link(url.absoluteString, destination: url)
                    .font(.callout)
            }
        case .reference, .prompt:
            EmptyView()
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// One attached node in the Idea's grid: a picture (media, cover, circle or text) over its title,
/// with the category strip on top like its card.
private struct AttachedTile: View {
    let node: CanvasNode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(node.category?.color ?? Color.primary.opacity(0.12))
                .frame(height: 4)
            preview
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(node.displayTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, Theme.unit)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        }
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var preview: some View {
        switch node.kind {
        case .reference, .prompt:
            if let reference = node.reference {
                if reference.hasMedia {
                    ThumbnailImage(url: reference.mediaURL, pointSize: 220)
                } else {
                    TypographicCover(text: reference.copyablePrompt ?? "", background: node.category?.hexColor)
                }
            }
        case .idea:
            Circle()
                .fill(node.category?.color ?? Theme.neutralIdea)
                .frame(width: 88, height: 88)
                .overlay {
                    Text(node.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(node.category?.hexColor?.textColor ?? Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(10)
                }
        case .note, .text:
            Text(node.body ?? "")
                .font(.callout)
                .padding(Theme.unit * 1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .link:
            Image(systemName: "globe")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Transition

extension AnyTransition {
    /// Grows from `source` (a rect in the container, e.g. a node on the Map) to fill a
    /// container of `size`, and shrinks back into it. Without a source it fades.
    static func hero(from source: CGRect?, in size: CGSize) -> AnyTransition {
        guard let source, size.width > 0, size.height > 0 else { return .opacity }
        return .modifier(
            active: HeroEffect(source: source, size: size, progress: 0),
            identity: HeroEffect(source: source, size: size, progress: 1)
        )
    }
}

private struct HeroEffect: ViewModifier {
    let source: CGRect
    let size: CGSize
    /// 0 at the source, 1 full size.
    let progress: CGFloat

    func body(content: Content) -> some View {
        let scaleX = source.width / size.width
        let scaleY = source.height / size.height
        content
            .clipShape(RoundedRectangle(cornerRadius: progress == 1 ? 0 : Theme.cardCorner / max(min(scaleX, scaleY), 0.01)))
            .scaleEffect(
                x: scaleX + (1 - scaleX) * progress,
                y: scaleY + (1 - scaleY) * progress,
                anchor: .topLeading
            )
            .offset(x: source.minX * (1 - progress), y: source.minY * (1 - progress))
            .opacity(progress)
    }
}
