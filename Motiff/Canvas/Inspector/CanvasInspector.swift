import SwiftUI

/// Details for what's selected on the Map (⌥⌘I): its text, its category, and for References
/// the prompt's purpose and the tags. Each edit is one Undo step.
struct CanvasInspector: View {
    let controller: CanvasController

    var body: some View {
        let nodes = controller.selectedNodes
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.unit * 3) {
                if nodes.count == 1, let node = nodes.first {
                    NodeInspector(node: node, controller: controller)
                        .id(node.id)
                } else if nodes.count > 1 {
                    Text("\(nodes.count) selected")
                        .font(.headline)
                    DetailSection("Category") {
                        CategoryPicker(categories: controller.canvas.sortedCategories) { category in
                            nodes.allSatisfy { $0.category === category }
                        } choose: { category in
                            controller.update { CanvasGraph.setCategory(nodes, to: category) }
                        }
                    }
                } else {
                    Text("Select something on the Canvas to see its details here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NodeInspector: View {
    let node: CanvasNode
    let controller: CanvasController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.kind.label).motiffLabel()
                Text(node.displayTitle)
                    .font(.headline)
                    .lineLimit(3)
                Button("Open Full Size") { controller.openDetail(node.id) }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .help("Open (\(ShortcutCatalog.openDetail.keys))")
            }

            text

            DetailSection("Category") {
                CategoryPicker(categories: controller.canvas.sortedCategories) { category in
                    node.category === category
                } choose: { category in
                    controller.update { CanvasGraph.setCategory([node], to: category) }
                }
            }

            ConnectionList(node: node) { other in
                controller.focus(on: other.id)
            } detach: { child in
                controller.detach(child)
            } unlink: { link in
                controller.unlink(link)
            }

            if let reference = node.reference {
                DetailSection("Purpose") {
                    Picker("Purpose", selection: purpose(of: reference)) {
                        Text("None").tag(PromptPurpose?.none)
                        ForEach(PromptPurpose.allCases, id: \.self) { purpose in
                            Label(purpose.label, systemImage: purpose.systemImage).tag(Optional(purpose))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                DetailSection("Why") {
                    WhyChipToggles(selected: reference.why) { chip in
                        controller.update {
                            CanvasGraph.edit(node) { _ in
                                var why = reference.why
                                if let index = why.firstIndex(of: chip) { why.remove(at: index) } else { why.append(chip) }
                                reference.why = why
                            }
                        }
                    }
                    CommitField(prompt: "Why I kept it", value: reference.whyNote ?? "", axis: .vertical) { text in
                        controller.update {
                            CanvasGraph.edit(node) { _ in reference.whyNote = text.isEmpty ? nil : text }
                        }
                    }
                }
                if let tags = reference.readTags {
                    DetailSection("Read") {
                        ReadTagList(tags: tags)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        switch node.kind {
        case .idea:
            DetailSection("Title") {
                CommitField(prompt: "Untitled idea", value: node.title ?? "") { text in
                    controller.update { CanvasGraph.rename(node, to: text) }
                }
            }
            DetailSection("Description") {
                CommitField(prompt: "What this idea is about", value: node.body ?? "", axis: .vertical) { text in
                    controller.update { CanvasGraph.edit(node) { $0.body = text.isEmpty ? nil : text } }
                }
            }
        case .note:
            DetailSection("Text") {
                CommitField(prompt: "Markdown", value: node.body ?? "", axis: .vertical) { text in
                    controller.update { CanvasGraph.edit(node) { $0.body = text } }
                }
            }
        case .text:
            DetailSection("Text") {
                CommitField(prompt: "Text", value: node.body ?? "", axis: .vertical) { text in
                    controller.update { CanvasGraph.edit(node) { $0.body = text } }
                }
            }
            DetailSection("Size") {
                TextSizePicker(controller: controller, node: node)
            }
        case .link:
            DetailSection("Title") {
                CommitField(prompt: "Title", value: node.title ?? "") { text in
                    controller.update { CanvasGraph.edit(node) { $0.title = text.isEmpty ? nil : text } }
                }
            }
            DetailSection("URL") {
                CommitField(prompt: "https://", value: node.urlString ?? "") { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    controller.update { CanvasGraph.edit(node) { $0.urlString = trimmed.isEmpty ? nil : trimmed } }
                }
            }
        case .reference, .prompt:
            if let prompt = node.reference?.copyablePrompt {
                DetailSection("Prompt") {
                    PromptBlock(prompt: prompt)
                }
            }
        }
    }

    private func purpose(of reference: Reference) -> Binding<PromptPurpose?> {
        Binding {
            reference.purpose
        } set: { purpose in
            controller.update { CanvasGraph.edit(node) { _ in reference.purpose = purpose } }
        }
    }
}

// MARK: - Building blocks

/// The Canvas's categories as rows with their color, a check on the current one, and None.
/// Small, Medium, Large, Huge for a Text node. One Undo step each.
struct TextSizePicker: View {
    let controller: CanvasController
    let node: CanvasNode

    var body: some View {
        Picker("Size", selection: Binding(get: { node.textSize }, set: { controller.setTextSize($0, of: node.id) })) {
            ForEach(TextSize.allCases) { size in
                Text(size.label).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct CategoryPicker: View {
    let categories: [CanvasCategory]
    let isOn: (CanvasCategory?) -> Bool
    let choose: (CanvasCategory?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(categories) { category in
                row(category.name, color: category.color, isOn: isOn(category)) { choose(category) }
            }
            row("None", color: nil, isOn: isOn(nil)) { choose(nil) }
        }
    }

    private func row(_ name: String, color: Color?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.unit) {
                Circle()
                    .fill(color ?? .clear)
                    .overlay { Circle().strokeBorder(Color.primary.opacity(color == nil ? 0.35 : 0), lineWidth: 1) }
                    .frame(width: 10, height: 10)
                Text(name)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .font(.callout)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// What Claude read from the image, one line per tag it found.
private struct ReadTagList: View {
    let tags: ReadTags

    private struct Row: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }

    private var rows: [Row] {
        let all: [(String, String?)] = [
            ("Type", tags.type), ("Style", tags.style), ("Composition", tags.composition),
            ("Typeface", tags.typography), ("Texture", tags.textureDescription),
            ("Light", tags.lighting), ("Mood", tags.mood),
        ]
        return all.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return Row(key: key, value: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    Text(row.value)
                        .font(.callout)
                }
            }
        }
    }
}

/// A text field that saves when you press Return or leave it, not on every keystroke,
/// so a whole edit is one Undo step.
struct CommitField: View {
    let prompt: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $draft, axis: axis)
            .textFieldStyle(.roundedBorder)
            .lineLimit(axis == .vertical ? 2...8 : 1...1)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if !focused { draft = newValue }
            }
            .onSubmit(save)
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused, !isFocused { save() }
            }
    }

    private func save() {
        if draft != value { commit(draft) }
    }
}
