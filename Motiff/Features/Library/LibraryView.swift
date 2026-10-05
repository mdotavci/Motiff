import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct LibraryView: View {
    /// A Reference to open, asked for from outside (the ⌘K palette); cleared once opened.
    var pending: Binding<Reference?> = .constant(nil)

    @State private var path: [Reference] = []

    var body: some View {
        NavigationStack(path: $path) {
            ReferenceCollectionView()
                .navigationDestination(for: Reference.self) { reference in
                    ReferenceDetailView(reference: reference)
                }
                .onAppear(perform: openPending)
                .onChange(of: pending.wrappedValue?.id) { openPending() }
        }
    }

    private func openPending() {
        guard let reference = pending.wrappedValue else { return }
        pending.wrappedValue = nil
        path = [reference]
    }
}

/// The Library's grid, or one Board's. Drop, paste or import (⌘O) to add: into the Library,
/// and onto the Board when it's a Board's. Put it in a NavigationStack that opens References.
struct ReferenceCollectionView: View {
    /// Show this Board's References instead of the whole Library.
    var board: Board?

    @Environment(\.modelContext) private var context
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @Query(sort: \Board.name) private var boards: [Board]
    @AppStorage(LibraryDensity.storageKey) private var densityLevel = LibraryDensity.defaultLevel

    @State private var availableWidth: CGFloat = 0
    @State private var pendingDelete: Reference?
    /// Show only prompts with this purpose; nil shows everything.
    @State private var purposeFilter: PromptPurpose?
    @State private var isDropTargeted = false
    @State private var isImporting = false
    /// Just saved, waiting for a Why.
    @State private var justSaved: [Reference] = []
    #if os(iOS)
    @State private var showsPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsLibraryPicker = false
    #endif

    var body: some View {
        content
            .navigationTitle(board?.displayName ?? "Library")
            #if os(macOS)
            .navigationSubtitle(subtitle)
            #endif
            .toolbar {
                addMenu
                #if os(macOS)
                purposeMenu
                densityControls
                #endif
            }
            // Drag in from Finder or a browser; a light outline shows it'll land.
            .onDrop(of: CaptureService.acceptedTypes, isTargeted: $isDropTargeted) { providers in
                Task { await capture(CaptureService.items(from: providers)) }
                return true
            }
            .overlay {
                if isDropTargeted {
                    Rectangle()
                        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            #if os(macOS)
            .onPasteCommand(of: CaptureService.acceptedTypes) { providers in
                Task { await capture(CaptureService.items(from: providers)) }
            }
            #endif
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                Task { await capture(urls.map { CaptureItem.file($0) }) }
            }
            .focusedSceneValue(\.importFiles, ImportAction { isImporting = true })
            .sheet(isPresented: isAskingWhy) {
                WhySheet(references: justSaved)
            }
            #if os(iOS)
            .photosPicker(isPresented: $showsPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await capture(await CaptureService.items(from: items)) }
            }
            .sheet(isPresented: $showsLibraryPicker) {
                LibraryDrawer { reference in
                    board?.add([reference])
                    try? context.save()
                } close: {
                    showsLibraryPicker = false
                }
                .presentationDetents([.medium, .large])
            }
            #endif
    }

    /// Images and videos from files (and, on iPhone, Photos); on a Board, also from the Library.
    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            #if os(macOS)
            Button("Add Images", systemImage: "plus") { isImporting = true }
                .help("Add images or videos (\(ShortcutCatalog.importFiles.keys)); or drop them here")
            #else
            Menu("Add", systemImage: "plus") {
                Button("Photos and Videos…", systemImage: "photo.on.rectangle") { showsPhotos = true }
                Button("Files…", systemImage: "folder") { isImporting = true }
                if board != nil {
                    Button("From the Library…", systemImage: "square.grid.2x2") { showsLibraryPicker = true }
                }
            }
            #endif
        }
    }

    private var isAskingWhy: Binding<Bool> {
        Binding { !justSaved.isEmpty } set: { if !$0 { justSaved = [] } }
    }

    /// Saves what came in as References (on the Board too, on a Board's), then asks why.
    /// Links have nowhere to go in the Library (they're Canvas cards), so they're skipped.
    /// References dragged from the Library are already in it: a Board just takes them.
    private func capture(_ items: [CaptureItem]) async {
        var existing: [Reference] = []
        var rest: [CaptureItem] = []
        for item in items {
            if case let .text(text) = item, let id = LibraryDrag.referenceID(in: text) {
                if let reference = references.first(where: { $0.id == id }) { existing.append(reference) }
            } else {
                rest.append(item)
            }
        }
        if let board, !existing.isEmpty {
            board.add(existing)
            try? context.save()
        }
        guard !rest.isEmpty else { return }
        let prepared = await CapturePrep.prepare(rest)
        let saved = prepared.compactMap { CaptureService.makeReference($0, in: context) }
        guard !saved.isEmpty else { return }
        board?.add(saved)
        try? context.save()
        justSaved = saved
    }

    @ViewBuilder
    private var content: some View {
        if shown.isEmpty, purposeFilter != nil {
            EmptyState(title: board?.displayName ?? "Library", message: "No \(purposeFilter?.label.lowercased() ?? "") prompts yet.")
        } else if shown.isEmpty, board != nil {
            EmptyState(title: board?.displayName ?? "Board", message: Self.emptyBoardMessage)
        } else if shown.isEmpty {
            EmptyState(title: "Library", message: "Everything you keep.")
        } else {
            ScrollView {
                MasonryGrid(
                    items: shown,
                    columns: columnCount,
                    spacing: Theme.gridGap,
                    aspectRatio: \.displayAspectRatio
                ) { reference in
                    NavigationLink(value: reference) {
                        ReferenceTile(reference: reference, width: tileWidth)
                    }
                    .buttonStyle(.plain)
                    // Onto a Board in the sidebar, or onto a Canvas.
                    .draggable(LibraryDrag.payload(for: reference)) {
                        ReferenceTile(reference: reference, width: 120)
                    }
                    .contextMenu {
                        if let board {
                            Button("Remove from Board", systemImage: "minus.circle") {
                                board.remove(reference)
                                try? context.save()
                            }
                            Divider()
                        }
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

    private var shown: [Reference] {
        let all = board?.sortedReferences ?? references
        guard let purposeFilter else { return all }
        return all.filter { $0.purpose == purposeFilter }
    }

    #if os(macOS)
    private static let emptyBoardMessage = "Drop images here, paste them (⌘V) or add them with +. Or drag references from the Library onto this board in the sidebar."
    #else
    private static let emptyBoardMessage = "Tap + to add photos, files, or references from the Library."
    #endif

    private var subtitle: String {
        let count = shown.count == 1 ? "1 reference" : "\(shown.count) references"
        guard let purposeFilter else { return count }
        return "\(count) · \(purposeFilter.label) prompts"
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
    /// All, or only Image / Text / Code / Other prompts.
    @ToolbarContentBuilder
    private var purposeMenu: some ToolbarContent {
        ToolbarItem {
            Picker("Purpose", selection: $purposeFilter) {
                Text("All").tag(PromptPurpose?.none)
                Divider()
                ForEach(PromptPurpose.allCases, id: \.self) { purpose in
                    Label(purpose.label, systemImage: purpose.systemImage).tag(Optional(purpose))
                }
            }
            .pickerStyle(.menu)
            .help("Show only prompts for one purpose")
        }
    }

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
