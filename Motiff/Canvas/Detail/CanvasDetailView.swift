import SwiftUI
import UniformTypeIdentifiers

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
                Label(controller.detailPath.count > 1 ? "Back" : "Board", systemImage: "chevron.left")
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

// MARK: - Ideas, notes, text and links

/// An Idea, Note, Text or Link full size, with everything editable in place: its title, its
/// text in a markdown editor with a formatting bar, its category and color, a Link's address,
/// a Text's size. Under it, everything attached to it as a grid, with + tiles to add more.
private struct IdeaDetailView: View {
    let node: CanvasNode
    let controller: CanvasController

    @State private var isImporting = false
    @State private var showsLibrary = false
    @State private var showsColors = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.unit * 3) {
                VStack(alignment: .leading, spacing: Theme.unit * 1.5) {
                    look
                    if node.kind == .idea || node.kind == .link {
                        TitleField(
                            prompt: node.kind == .idea ? "Name this idea" : "Title",
                            value: node.title ?? ""
                        ) { text in
                            if node.kind == .idea {
                                controller.update { CanvasGraph.rename(node, to: text) }
                            } else {
                                controller.update { CanvasGraph.edit(node) { $0.title = text.isEmpty ? nil : text } }
                            }
                        }
                    }
                }

                text

                if node.kind == .idea {
                    attached
                }

                ConnectionList(node: node) { other in
                    controller.openDetail(other.id)
                }
            }
            .padding(Theme.gutter * 2)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            let id = node.id
            Task { await controller.capture(urls.map { CaptureItem.file($0) }, at: nil, onto: id) }
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryDrawer { reference in
                controller.place(references: [reference.id], onto: node.id)
            } close: {
                showsLibrary = false
            }
            .frame(minWidth: 320, minHeight: 480)
            .presentationDetents([.medium, .large])
        }
    }

    /// Kind, category and color in one row: what it is and how it looks.
    private var look: some View {
        HStack(spacing: Theme.unit) {
            Text(node.kind.label).motiffLabel()
            Menu {
                ForEach(controller.canvas.sortedCategories) { category in
                    Button {
                        controller.update { CanvasGraph.setCategory([node], to: category) }
                    } label: {
                        if node.category === category {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
                Divider()
                Button("No Category") {
                    controller.update { CanvasGraph.setCategory([node], to: nil) }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(node.category?.color ?? Color.primary.opacity(0.15))
                        .frame(width: 9, height: 9)
                    Text(node.category?.name ?? "No category")
                }
                .font(.callout)
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("Category")

            Button {
                showsColors = true
            } label: {
                Group {
                    if let hex = node.kind == .text ? node.textColorHex : node.effectiveColorHex {
                        SwatchDot(hex: hex, size: 16)
                    } else {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Color (\(ShortcutCatalog.color.keys) on the Map)")
            .popover(isPresented: $showsColors, arrowEdge: .bottom) {
                ColorPalettePicker(
                    current: node.kind == .text ? node.textColorHex : node.colorHex,
                    resetTitle: node.kind == .text ? "Automatic" : "Category Color"
                ) { hex in
                    controller.select(node.id)
                    controller.setColor(hex)
                }
                .padding(12)
                .frame(width: 280)
            }

            if node.kind == .text {
                TextSizePicker(controller: controller, node: node)
                    .frame(width: 260)
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        switch node.kind {
        case .idea:
            MarkdownEditor(value: node.body ?? "", prompt: "What this idea is about: notes, links, a plan…") { text in
                controller.update { CanvasGraph.edit(node) { $0.body = text.isEmpty ? nil : text } }
            }
            .frame(maxWidth: 720)
        case .note, .text:
            MarkdownEditor(
                value: node.body ?? "",
                prompt: node.kind == .note ? "Write the note…" : "Write the text…",
                minHeight: 260,
                font: node.kind == .note ? .title3 : .body
            ) { text in
                controller.update { CanvasGraph.edit(node) { $0.body = text } }
            }
            .frame(maxWidth: 720)
        case .link:
            VStack(alignment: .leading, spacing: Theme.unit) {
                CommitField(prompt: "https://", value: node.urlString ?? "") { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    controller.update { CanvasGraph.edit(node) { $0.urlString = trimmed.isEmpty ? nil : trimmed } }
                }
                .frame(maxWidth: 520)
                if let url = node.url {
                    Link("Open \(url.host() ?? url.absoluteString)", destination: url)
                        .font(.callout)
                }
            }
        case .reference, .prompt:
            EmptyView()
        }
    }

    /// Everything that belongs to the Idea, then tiles that add a Note, Text, Idea or images.
    private var attached: some View {
        let children = node.sortedChildren
        return DetailSection(children.isEmpty ? "Attached" : "Attached · \(children.count)") {
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
                AddTile(title: "Note", systemImage: "note.text") { add(.note) }
                AddTile(title: "Text", systemImage: "textformat") { add(.text) }
                AddTile(title: "Sub-Idea", systemImage: "circle") { add(.idea) }
                AddTile(title: "Images", systemImage: "photo") { isImporting = true }
                AddTile(title: "From Library", systemImage: "square.grid.2x2") { showsLibrary = true }
            }
        }
    }

    /// A new Note, Text or Idea on this Idea, opened full size to write in.
    private func add(_ kind: NodeKind) {
        controller.addChild(kind, to: node.id)
    }
}

/// A big plain text field for a title. Saves on Return or when it loses focus.
private struct TitleField: View {
    let prompt: String
    let value: String
    let commit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 28, weight: .semibold))
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if !focused { draft = newValue }
            }
            .onSubmit(save)
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused, !isFocused { save() }
            }
            .onDisappear(perform: save)
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { commit(trimmed) }
    }
}

/// A dashed tile in the Attached grid that adds something.
private struct AddTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Label(title, systemImage: systemImage)
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        }
        .buttonStyle(.plain)
        .help("Add \(title)")
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
