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

/// The Library's grid. Drop, paste or import (⌘O) to add. Put it in a NavigationStack that
/// opens References.
struct ReferenceCollectionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @Query(sort: \Canvas.createdAt) private var boards: [Canvas]
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
    #endif

    var body: some View {
        content
            .navigationTitle("Library")
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
            #endif
    }

    /// Images and videos from files (and, on iPhone, Photos).
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
            }
            #endif
        }
    }

    private var isAskingWhy: Binding<Bool> {
        Binding { !justSaved.isEmpty } set: { if !$0 { justSaved = [] } }
    }

    /// Saves what came in as References, then asks why. Links have nowhere to go in the Library
    /// (they're board cards), so they're skipped. References dragged from the Library itself are
    /// already in it.
    private func capture(_ items: [CaptureItem]) async {
        let rest = items.filter { item in
            if case let .text(text) = item, LibraryDrag.referenceID(in: text) != nil { return false }
            return true
        }
        guard !rest.isEmpty else { return }
        let prepared = await CapturePrep.prepare(rest)
        let saved = prepared.compactMap { CaptureService.makeReference($0, in: context) }
        guard !saved.isEmpty else { return }
        try? context.save()
        justSaved = saved
    }

    @ViewBuilder
    private var content: some View {
        if shown.isEmpty, purposeFilter != nil {
            EmptyState(title: "Library", message: "No \(purposeFilter?.label.lowercased() ?? "") prompts yet.")
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
                    // Onto a board in the sidebar, or onto an open board.
                    .draggable(LibraryDrag.payload(for: reference)) {
                        ReferenceTile(reference: reference, width: 120)
                    }
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

    private var shown: [Reference] {
        guard let purposeFilter else { return references }
        return references.filter { $0.purpose == purposeFilter }
    }

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
        case 0: "The media file is removed too."
        case 1: "Its remix is deleted too. The media files are removed."
        default: "Its \(remixes) remixes are deleted too. The media files are removed."
        }
        let canvases = switch reference.canvasCountWithRemixes {
        case 0: ""
        case 1: " It's also taken off the board it's on."
        case let count: " It's also taken off the \(count) boards it's on."
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
