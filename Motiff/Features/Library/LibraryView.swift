import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @Query(sort: \Board.name) private var boards: [Board]
    @AppStorage(LibraryDensity.storageKey) private var densityLevel = LibraryDensity.defaultLevel

    /// A Reference to open, asked for from outside (the ⌘K palette); cleared once opened.
    var pending: Binding<Reference?> = .constant(nil)

    @State private var path: [Reference] = []
    @State private var availableWidth: CGFloat = 0
    @State private var pendingDelete: Reference?
    /// Show only prompts with this purpose; nil shows everything.
    @State private var purposeFilter: PromptPurpose?
    @State private var isDropTargeted = false
    @State private var isImporting = false
    /// Just saved, waiting for a Why.
    @State private var justSaved: [Reference] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Library")
                #if os(macOS)
                .navigationSubtitle(subtitle)
                .toolbar {
                    purposeMenu
                    densityControls
                }
                #endif
                .navigationDestination(for: Reference.self) { reference in
                    ReferenceDetailView(reference: reference)
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
                .onAppear(perform: openPending)
                .onChange(of: pending.wrappedValue?.id) { openPending() }
                .sheet(isPresented: isAskingWhy) {
                    WhySheet(references: justSaved)
                }
        }
    }

    private func openPending() {
        guard let reference = pending.wrappedValue else { return }
        pending.wrappedValue = nil
        path = [reference]
    }

    private var isAskingWhy: Binding<Bool> {
        Binding { !justSaved.isEmpty } set: { if !$0 { justSaved = [] } }
    }

    /// Saves what came in as References, then asks why. Links have nowhere to go in the
    /// Library (they're Canvas cards), so they're skipped.
    private func capture(_ items: [CaptureItem]) async {
        let prepared = await CapturePrep.prepare(items)
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
