import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One Reference, full size, as the Library shows it. The Canvas shows the same
/// `ReferenceDetailContent` with its own header and a Connections section.
struct ReferenceDetailView: View {
    let reference: Reference

    var body: some View {
        ReferenceDetailContent(reference: reference) { EmptyView() }
            .navigationTitle(reference.origin.label)
            #if os(macOS)
            .navigationSubtitle(reference.createdAt.formatted(date: .abbreviated, time: .omitted))
            #endif
            .toolbar {
                ToolbarItemGroup {
                    if let prompt = reference.promptToCopy {
                        Button("Copy Prompt", systemImage: "text.quote") { Pasteboard.copy(prompt) }
                            .help("Copy the prompt, with its model's parameters")
                    }
                    if reference.hasMedia {
                        #if os(macOS)
                        Button("Show in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([reference.mediaURL])
                        }
                        .help("Show the media file in Finder")
                        #endif
                        ShareLink(item: reference.mediaURL)
                    } else if let prompt = reference.copyablePrompt {
                        ShareLink(item: prompt)
                    }
                }
            }
    }
}

/// Media and details. Wide windows put the media on the left and the details in a column on
/// the right; narrow ones stack them. `extra` goes under the details.
struct ReferenceDetailContent<Extra: View>: View {
    let reference: Reference
    let extra: Extra

    @State private var width: CGFloat = 0

    private static var sideColumnWidth: CGFloat { 360 }

    init(reference: Reference, @ViewBuilder extra: () -> Extra) {
        self.reference = reference
        self.extra = extra()
    }

    var body: some View {
        Group {
            if width >= 760 {
                HStack(spacing: 0) {
                    ReferenceMediaView(reference: reference)
                        .padding(Theme.gutter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.04))
                    Divider()
                    ScrollView {
                        info
                            .padding(Theme.gutter)
                    }
                    .frame(width: Self.sideColumnWidth)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ReferenceMediaView(reference: reference)
                            .aspectRatio(reference.mediaAspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        info
                            .padding(Theme.gutter)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear {
            if reference.openedAt == nil { reference.openedAt = .now }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 3) {
            ReferenceInfo(reference: reference)
            extra
        }
    }
}

/// Opens a Reference from inside its detail (a Remix in Lineage). Where it isn't set, the
/// links push onto the surrounding NavigationStack.
struct OpenReferenceAction: Sendable {
    let open: @MainActor @Sendable (Reference) -> Void
}

private struct OpenReferenceKey: EnvironmentKey {
    static let defaultValue: OpenReferenceAction? = nil
}

extension EnvironmentValues {
    var openReference: OpenReferenceAction? {
        get { self[OpenReferenceKey.self] }
        set { self[OpenReferenceKey.self] = newValue }
    }
}

/// The text side of the detail view: Prompt, Notes, Why, Purpose and Source, all editable in
/// place (⌘Z undoes); then Read, Lineage and Boards, which are worked out.
struct ReferenceInfo: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 3) {
            header

            DetailSection(reference.recipe.isEmpty ? "Prompt" : "Recipe") { RecipeCard(reference: reference) }

            DetailSection("Details") { PromptDetails(reference: reference) }

            DetailSection(reference.promptVariants.isEmpty ? "Versions" : "Versions · \(reference.promptVariants.count)") {
                PromptVariants(reference: reference)
            }

            DetailSection("Notes") { notes }

            DetailSection("Why") { WhyEditor(reference: reference) }

            DetailSection("Purpose") { purposePicker }

            DetailSection("Source") { SourceCard(reference: reference) }

            DetailSection("Read") { ReadCard(reference: reference) }

            if reference.parent != nil || !reference.children.isEmpty {
                DetailSection("Lineage") { LineageCard(reference: reference) }
            }

            let boards = Set(reference.canvasNodes.compactMap { $0.canvas?.displayTitle }).sorted()
            if !boards.isEmpty {
                DetailSection("Boards") {
                    Text(boards.joined(separator: ", "))
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notes: some View {
        MarkdownEditor(value: reference.notes ?? "", prompt: "Your notes on it: what to take from it, where to use it…", minHeight: 140) { text in
            reference.edit { $0.notes = text.isEmpty ? nil : text }
        }
    }

    private var purposePicker: some View {
        Picker("Purpose", selection: purpose) {
            Text("None").tag(PromptPurpose?.none)
            ForEach(PromptPurpose.allCases, id: \.self) { purpose in
                Label(purpose.label, systemImage: purpose.systemImage).tag(PromptPurpose?.some(purpose))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var purpose: Binding<PromptPurpose?> {
        Binding {
            reference.purpose
        } set: { purpose in
            reference.edit { $0.purpose = purpose }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.unit) {
            OriginBadge(origin: reference.origin)
            Text("\(reference.origin.label) · Saved \(reference.createdAt, format: .relative(presentation: .named))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Building blocks

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(title).motiffLabel()
            content
        }
    }
}

/// A key on the left, a selectable value on the right.
private struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.unit) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Monospaced prompt with a Copy button that confirms for a moment.
struct PromptBlock: View {
    let prompt: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(prompt)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                Pasteboard.copy(prompt)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(Theme.unit * 1.5)
        .background(Color.primary.opacity(0.05))
    }
}

// MARK: - Sections

private struct RecipeCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            ForEach(reference.recipe) { part in
                KeyValueRow(key: part.kind.label, value: part.text)
            }
            PromptEditor(reference: reference)
            if reference.recipeIsDescribed {
                Text("Described from the image by AI, not the original prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReadCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            if let tags = reference.readTags {
                ForEach(rows(tags), id: \.key) { row in
                    KeyValueRow(key: row.key, value: row.value)
                }
                if !tags.paletteHex.isEmpty {
                    PaletteRow(hexes: tags.paletteHex)
                }
            } else {
                status
            }
            if let text = reference.ocrText, !text.isEmpty {
                KeyValueRow(key: "Text", value: text)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch reference.aiState {
        case .pending:
            Text("Not read yet.").font(.callout).foregroundStyle(.secondary)
        case .done:
            Text("Nothing read.").font(.callout).foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: Theme.unit) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                Text("Couldn't read this.").font(.callout)
            }
        }
    }

    private struct Row {
        let key: String
        let value: String
    }

    private func rows(_ tags: ReadTags) -> [Row] {
        let pairs: [(String, String?)] = [
            ("Type", tags.type),
            ("Style", tags.style),
            ("Composition", tags.composition),
            ("Typography", tags.typography),
            ("Texture", tags.textureDescription),
            ("Lighting", tags.lighting),
            ("Mood", tags.mood),
        ]
        return pairs.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return Row(key: key, value: value)
        }
    }
}

/// Colour swatches. Click one to copy its hex.
private struct PaletteRow: View {
    let hexes: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(hexes, id: \.self) { hex in
                if let color = Color(hex: hex) {
                    Button {
                        Pasteboard.copy(hex)
                    } label: {
                        Rectangle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(hex)")
                    .accessibilityLabel("Colour \(hex)")
                    .accessibilityHint("Copies the hex value")
                }
            }
        }
    }
}

/// The Why chips to tap on and off, and the one-line Why note.
private struct WhyEditor: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            WhyChipToggles(selected: reference.why) { chip in
                reference.edit { reference in
                    if reference.why.contains(chip) {
                        reference.why.removeAll { $0 == chip }
                    } else {
                        reference.why.append(chip)
                    }
                }
            }
            CommitField(prompt: "Why I kept it", value: reference.whyNote ?? "") { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                reference.edit { $0.whyNote = trimmed.isEmpty ? nil : trimmed }
            }
        }
    }
}

/// The prompt as text you can change, in mono, with Copy. Saved a moment after typing stops
/// and when it loses focus; ⌘Z undoes.
private struct PromptEditor: View {
    let reference: Reference

    @State private var draft = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            TextField("Write or paste the prompt", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .lineLimit(3...20)
                .focused($focused)
                .onAppear { draft = reference.copyablePrompt ?? "" }
                .onChange(of: reference.copyablePrompt) { _, prompt in
                    if !focused { draft = prompt ?? "" }
                }
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused, !isFocused { save() }
                }
                .onDisappear(perform: save)
            HStack {
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    save()
                    Pasteboard.copy(reference.promptToCopy ?? draft)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .disabled(draft.isEmpty)
                Spacer()
                if focused {
                    Button("Done") { focused = false }
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(Theme.unit * 1.5)
        .background(Color.primary.opacity(0.05))
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != (reference.copyablePrompt ?? "") else { return }
        reference.edit { $0.promptRaw = text.isEmpty ? nil : text }
    }
}

/// Where it came from: the address and who made it, both editable, and a link to open it.
private struct SourceCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            if let platform = reference.sourcePlatform, !platform.isEmpty {
                KeyValueRow(key: "From", value: platform)
            }
            CommitField(prompt: "Link (https://…)", value: reference.sourceURL ?? "") { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                reference.edit { $0.sourceURL = trimmed.isEmpty ? nil : trimmed }
            }
            CommitField(prompt: "Creator", value: reference.creator ?? "") { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                reference.edit { $0.creator = trimmed.isEmpty ? nil : trimmed }
            }
            if let string = reference.sourceURL, let url = URL(string: string), url.scheme != nil {
                Link("Open \(url.host() ?? string)", destination: url)
                    .font(.callout)
            }
        }
    }
}

private struct LineageCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            if let parent = reference.parent {
                LineageLink(reference: parent, caption: "Remixed from")
            }
            ForEach(reference.children.sorted { $0.createdAt < $1.createdAt }) { child in
                LineageLink(reference: child, caption: "Remix")
            }
        }
    }
}

private struct LineageLink: View {
    let reference: Reference
    let caption: String

    @Environment(\.openReference) private var openReference

    var body: some View {
        if let openReference {
            Button { openReference.open(reference) } label: { row }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: reference) { row }
                .buttonStyle(.plain)
        }
    }

    private var row: some View {
        HStack(spacing: Theme.unit) {
            ThumbnailImage(url: reference.mediaURL, pointSize: 44)
                .frame(width: 44, height: 44)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(reference.origin.label).font(.callout)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

extension Color {
    /// `#RRGGBB` or `RRGGBB`.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The prompt's model and settings, all editable: the usual ones (negative prompt, aspect
/// ratio, seed, parameters), then fields of your own. Copy Prompt adds them in the model's
/// own syntax (`PromptSettings.formatted`).
private struct PromptDetails: View {
    let reference: Reference

    var body: some View {
        let settings = reference.promptSettings
        VStack(alignment: .leading, spacing: Theme.unit) {
            HStack(spacing: Theme.unit) {
                label("Model")
                CommitField(prompt: "Which model or tool", value: reference.model ?? "") { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    reference.edit { $0.model = trimmed.isEmpty ? nil : trimmed }
                }
                Menu {
                    ForEach(PromptSettings.suggestedModels, id: \.self) { name in
                        Button(name) { reference.edit { $0.model = name } }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pick a model")
            }
            ForEach(PromptSettings.Known.allCases, id: \.self) { key in
                HStack(spacing: Theme.unit) {
                    label(key.rawValue)
                    CommitField(prompt: key.placeholder, value: settings.known[key] ?? "") { text in
                        update { $0.known[key] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                }
            }
            ForEach(Array(settings.custom.enumerated()), id: \.offset) { index, field in
                HStack(spacing: Theme.unit) {
                    CommitField(prompt: "Name", value: field.key) { text in
                        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        update { settings in
                            guard index < settings.custom.count, !name.isEmpty,
                                  !settings.custom.contains(where: { $0.key == name }) else { return }
                            settings.custom[index].key = name
                        }
                    }
                    .frame(width: 110)
                    CommitField(prompt: "Value", value: field.value) { text in
                        update { settings in
                            guard index < settings.custom.count else { return }
                            settings.custom[index].value = text
                        }
                    }
                    Button("Remove", systemImage: "minus.circle") {
                        update { settings in
                            guard index < settings.custom.count else { return }
                            settings.custom.remove(at: index)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            Button("Add a Field", systemImage: "plus") {
                update { $0.custom.append(PromptSettings.Field(key: $0.newFieldName(), value: "")) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .leading)
    }

    private func update(_ change: (inout PromptSettings) -> Void) {
        var settings = reference.promptSettings
        change(&settings)
        reference.edit { $0.promptSettings = settings }
    }
}

/// Other versions of the prompt: edit one, copy it, make it the main prompt, or remove it.
private struct PromptVariants: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            ForEach(Array(reference.promptVariants.enumerated()), id: \.offset) { index, variant in
                HStack(alignment: .top, spacing: Theme.unit) {
                    CommitField(prompt: "Another version", value: variant, axis: .vertical) { text in
                        reference.edit { reference in
                            guard index < reference.promptVariants.count else { return }
                            reference.promptVariants[index] = text
                        }
                    }
                    .font(.callout.monospaced())
                    Menu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            Pasteboard.copy(reference.promptSettings.formatted(variant, model: reference.model))
                        }
                        Button("Make It the Main Prompt", systemImage: "arrow.up.circle") { makeMain(index) }
                        Divider()
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            reference.edit { reference in
                                guard index < reference.promptVariants.count else { return }
                                reference.promptVariants.remove(at: index)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            Button("Add a Version", systemImage: "plus") {
                reference.edit { $0.promptVariants.append($0.copyablePrompt ?? "") }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .help("A copy of the prompt to change and try")
        }
    }

    /// Swaps a version with the main prompt, so nothing is lost.
    private func makeMain(_ index: Int) {
        reference.edit { reference in
            guard index < reference.promptVariants.count else { return }
            let main = reference.copyablePrompt ?? ""
            reference.promptRaw = reference.promptVariants[index]
            reference.promptVariants[index] = main
        }
    }
}
