import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One Reference, full size. Wide windows put the media on the left and the details in a
/// column on the right; narrow ones stack them.
struct ReferenceDetailView: View {
    let reference: Reference

    @State private var width: CGFloat = 0

    private static let sideColumnWidth: CGFloat = 360

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
                        ReferenceInfo(reference: reference)
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
                        ReferenceInfo(reference: reference)
                            .padding(Theme.gutter)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(reference.origin.label)
        #if os(macOS)
        .navigationSubtitle(reference.createdAt.formatted(date: .abbreviated, time: .omitted))
        #endif
        .toolbar {
            ToolbarItemGroup {
                if let prompt = reference.copyablePrompt {
                    Button("Copy Prompt", systemImage: "text.quote") { Pasteboard.copy(prompt) }
                        .help("Copy the prompt")
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
        .onAppear {
            if reference.openedAt == nil { reference.openedAt = .now }
        }
    }
}

/// The text side of the detail view: Recipe, Read, Why, Source, Lineage, Boards.
/// Sections with nothing in them are left out.
struct ReferenceInfo: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 3) {
            header

            if !reference.recipe.isEmpty || reference.copyablePrompt != nil {
                DetailSection("Recipe") { RecipeCard(reference: reference) }
            }

            DetailSection("Read") { ReadCard(reference: reference) }

            if !reference.why.isEmpty || !(reference.whyNote ?? "").isEmpty {
                DetailSection("Why") { WhyCard(reference: reference) }
            }

            if hasSource {
                DetailSection("Source") { SourceCard(reference: reference) }
            }

            if reference.parent != nil || !reference.children.isEmpty {
                DetailSection("Lineage") { LineageCard(reference: reference) }
            }

            if !reference.boards.isEmpty {
                DetailSection("Boards") {
                    Text(reference.boards.map(\.name).sorted().joined(separator: ", "))
                        .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: Theme.unit) {
            OriginBadge(origin: reference.origin)
            Text("\(reference.origin.label) · Saved \(reference.createdAt, format: .relative(presentation: .named))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var hasSource: Bool {
        [reference.sourcePlatform, reference.sourceURL, reference.creator]
            .contains { !($0 ?? "").isEmpty }
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
            if let prompt = reference.copyablePrompt {
                PromptBlock(prompt: prompt)
            }
            if let model = reference.model, !model.isEmpty {
                KeyValueRow(key: "Model", value: model)
            }
            let settings = reference.settings
            ForEach(settings.keys.sorted(), id: \.self) { key in
                KeyValueRow(key: key, value: settings[key] ?? "")
            }
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

private struct WhyCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            if !reference.why.isEmpty {
                HStack(spacing: Theme.unit / 2) {
                    ForEach(reference.why, id: \.self) { chip in
                        Text(chip.label)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, Theme.unit)
                            .padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3)))
                    }
                }
            }
            if let note = reference.whyNote, !note.isEmpty {
                Text("“\(note)”")
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SourceCard: View {
    let reference: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            if let platform = reference.sourcePlatform, !platform.isEmpty {
                KeyValueRow(key: "From", value: platform)
            }
            if let creator = reference.creator, !creator.isEmpty {
                KeyValueRow(key: "Creator", value: creator)
            }
            if let string = reference.sourceURL, let url = URL(string: string) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.unit) {
                    Text("Link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    Link(string, destination: url)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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

    var body: some View {
        NavigationLink(value: reference) {
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
        .buttonStyle(.plain)
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
