import SwiftData
import SwiftUI

/// How a Reference travels from the Library panel to the Map: as text naming its id, which the
/// Map's drop reads back. Plain text, so it needs no custom type, and it can't be mistaken for a
/// prompt: nobody types this.
enum LibraryDrag {
    static let prefix = "motiff-reference:"

    static func payload(for reference: Reference) -> String {
        prefix + reference.id.uuidString
    }

    static func referenceID(in text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }
}

/// The Library beside the Map (⌥⌘L): every Reference as a small tile, newest first, with a
/// search and the purpose filter. Drag one onto the Map, or onto an Idea; or click it to put it
/// on the selected Idea. On iPhone it's a sheet, and a tap adds.
struct LibraryDrawer: View {
    /// Click (or tap): add this one.
    let pick: (Reference) -> Void
    var close: (() -> Void)?

    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @State private var search = ""
    @State private var purpose: PromptPurpose?

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 96), spacing: 6)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.unit) {
                Text("Library").font(.headline)
                Spacer()
                Menu {
                    Picker("Purpose", selection: $purpose) {
                        Text("All").tag(PromptPurpose?.none)
                        ForEach(PromptPurpose.allCases, id: \.self) { purpose in
                            Label(purpose.label, systemImage: purpose.systemImage).tag(PromptPurpose?.some(purpose))
                        }
                    }
                } label: {
                    Image(systemName: purpose == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show only one purpose")
                if let close {
                    Button("Close", systemImage: "xmark", action: close)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Hide the Library (\(ShortcutCatalog.libraryPanel.keys))")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, Theme.unit)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(shown) { reference in
                        LibraryDrawerTile(reference: reference)
                            .onTapGesture { pick(reference) }
                            .draggable(LibraryDrag.payload(for: reference)) {
                                LibraryDrawerTile(reference: reference).frame(width: 96, height: 96)
                            }
                            .help(reference.caption)
                    }
                }
                .padding(12)
            }
            .overlay {
                if shown.isEmpty {
                    Text(references.isEmpty ? "The Library is empty. Drop images on the Canvas to add some." : "Nothing matches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(Theme.gutter)
                }
            }
        }
    }

    private var shown: [Reference] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return references.filter { reference in
            if let purpose, reference.purpose != purpose { return false }
            guard !query.isEmpty else { return true }
            return reference.caption.localizedStandardContains(query)
                || (reference.copyablePrompt ?? "").localizedStandardContains(query)
                || (reference.whyNote ?? "").localizedStandardContains(query)
        }
    }
}

/// One square tile: the media, or the prompt's typographic cover.
private struct LibraryDrawerTile: View {
    let reference: Reference

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if reference.hasMedia {
                    ThumbnailImage(url: reference.mediaURL, pointSize: 120)
                } else {
                    TypographicCover(text: reference.copyablePrompt ?? "")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reference.caption)
            .accessibilityAddTraits(.isButton)
    }
}
