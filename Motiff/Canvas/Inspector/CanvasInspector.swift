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
            }

            text

            DetailSection("Category") {
                CategoryPicker(categories: controller.canvas.sortedCategories) { category in
                    node.category === category
                } choose: { category in
                    controller.update { CanvasGraph.setCategory([node], to: category) }
                }
            }

            Connections(node: node, controller: controller)

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

/// What the node belongs to and what it's linked with. Click a row to go to that node;
/// × detaches or unlinks.
private struct Connections: View {
    let node: CanvasNode
    let controller: CanvasController

    var body: some View {
        if let parent = node.parent {
            DetailSection("Belongs to") {
                ConnectionRow(node: parent, label: node.parentLabel, removeTitle: "Detach") {
                    controller.focus(on: parent.id)
                } remove: {
                    controller.detach(node)
                }
            }
        }
        let outgoing = node.outgoing.filter { $0.to != nil }
        if !outgoing.isEmpty {
            DetailSection("Linked to") {
                ForEach(outgoing) { link in
                    if let other = link.to {
                        ConnectionRow(node: other, label: link.label, removeTitle: "Unlink") {
                            controller.focus(on: other.id)
                        } remove: {
                            controller.unlink(link)
                        }
                    }
                }
            }
        }
        let incoming = node.incoming.filter { $0.from != nil }
        if !incoming.isEmpty {
            DetailSection("Linked from") {
                ForEach(incoming) { link in
                    if let other = link.from {
                        ConnectionRow(node: other, label: link.label, removeTitle: "Unlink") {
                            controller.focus(on: other.id)
                        } remove: {
                            controller.unlink(link)
                        }
                    }
                }
            }
        }
    }
}

private struct ConnectionRow: View {
    let node: CanvasNode
    let label: String?
    let removeTitle: String
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Theme.unit) {
            Button(action: open) {
                HStack(spacing: Theme.unit) {
                    Circle()
                        .fill(node.category?.color ?? Color.primary.opacity(0.25))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.displayTitle)
                            .lineLimit(1)
                        if let label, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to \(node.kind.label)")
            Button(removeTitle, systemImage: "xmark", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(removeTitle)
        }
        .padding(.vertical, 3)
    }
}

/// The Canvas's categories as rows with their color, a check on the current one, and None.
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

/// The eight Why chips; tap to turn one on or off. Black and white only.
private struct WhyChipToggles: View {
    let selected: [WhyChip]
    let toggle: (WhyChip) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(WhyChip.allCases, id: \.self) { chip in
                let isOn = selected.contains(chip)
                Button {
                    toggle(chip)
                } label: {
                    Text(chip.label)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(isOn ? Theme.canvasGround : Color.primary)
                        .background(isOn ? Color.primary : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
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
