import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @Query(sort: \Board.name) private var boards: [Board]
    @AppStorage(LibraryDensity.storageKey) private var densityLevel = LibraryDensity.defaultLevel

    @State private var availableWidth: CGFloat = 0
    @State private var pendingDelete: Reference?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                #if os(macOS)
                .navigationSubtitle(references.count == 1 ? "1 reference" : "\(references.count) references")
                .toolbar { densityControls }
                #endif
                .navigationDestination(for: Reference.self) { reference in
                    ReferenceDetailView(reference: reference)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if references.isEmpty {
            EmptyState(title: "Library", message: "Everything you keep.")
        } else {
            ScrollView {
                MasonryGrid(
                    items: references,
                    columns: columnCount,
                    spacing: Theme.gridGap,
                    aspectRatio: \.displayAspectRatio
                ) { reference in
                    NavigationLink(value: reference) {
                        ReferenceTile(reference: reference, width: tileWidth)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ReferenceMenu(reference: reference, boards: boards) {
                            pendingDelete = reference
                        }
                    }
                }
                .padding(Theme.gridGap)
                .animation(.default, value: columnCount)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .confirmationDialog(
                "Delete this reference?",
                isPresented: Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } },
                presenting: pendingDelete
            ) { reference in
                Button("Delete", role: .destructive) {
                    Reference.delete(reference, in: context)
                }
            } message: { reference in
                Text(deleteMessage(for: reference))
            }
        }
    }

    private var gridWidth: CGFloat {
        max(availableWidth - Theme.gridGap * 2, 0)
    }

    private var columnCount: Int {
        MasonryGrid<Reference, EmptyView>.columnCount(
            for: gridWidth,
            targetWidth: LibraryDensity.tileWidth(level: densityLevel),
            spacing: Theme.gridGap
        )
    }

    private var tileWidth: CGFloat {
        let columns = CGFloat(columnCount)
        return max((gridWidth - Theme.gridGap * (columns - 1)) / columns, 1)
    }

    private func deleteMessage(for reference: Reference) -> String {
        let remixes = reference.descendants.count
        let lineage = switch remixes {
        case 0: "The media file is removed too. Boards keep their other references."
        case 1: "Its remix is deleted too. The media files are removed."
        default: "Its \(remixes) remixes are deleted too. The media files are removed."
        }
        let canvases = switch reference.canvasCountWithRemixes {
        case 0: ""
        case 1: " It's also taken off the canvas it's on."
        case let count: " It's also taken off the \(count) canvases it's on."
        }
        return lineage + canvases
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var densityControls: some ToolbarContent {
        ToolbarItemGroup {
            ControlGroup {
                Button("Smaller", systemImage: "minus.magnifyingglass") {
                    densityLevel = LibraryDensity.clamped(densityLevel - 1)
                }
                .disabled(!LibraryDensity.canShrink(densityLevel))
                .help("Smaller thumbnails (⌘−)")

                Button("Larger", systemImage: "plus.magnifyingglass") {
                    densityLevel = LibraryDensity.clamped(densityLevel + 1)
                }
                // ⌘= as well as the menu's ⌘+, so zooming works without Shift.
                .keyboardShortcut("=")
                .disabled(!LibraryDensity.canGrow(densityLevel))
                .help("Larger thumbnails (⌘+)")
            }
        }
    }
    #endif
}
