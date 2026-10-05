#if os(macOS)
import SwiftData
import SwiftUI

enum SidebarItem: Hashable, CaseIterable {
    case inbox, library, boards, canvasGraph

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .library: "Library"
        case .boards: "Boards"
        case .canvasGraph: "Canvas Graph"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .library: "square.grid.2x2"
        case .boards: "rectangle.stack"
        case .canvasGraph: "point.3.filled.connected.trianglepath.dotted"
        }
    }

    var selection: SidebarSelection {
        switch self {
        case .inbox: .inbox
        case .library: .library
        case .boards: .boards
        case .canvasGraph: .canvasGraph
        }
    }
}

/// What the sidebar has selected: a fixed section, one Board, or one Canvas file.
enum SidebarSelection: Hashable {
    case inbox, library, boards, canvasGraph
    case board(UUID)
    case canvas(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Canvas.createdAt) private var canvases: [Canvas]
    @Query(sort: \Board.createdAt) private var boards: [Board]
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]
    @FocusedValue(\.importFiles) private var importFiles

    @State private var selection: SidebarSelection? = .library
    @State private var renaming: Canvas?
    @State private var draftTitle = ""
    @State private var pendingDelete: Canvas?
    @State private var renamingBoard: Board?
    @State private var pendingBoardDelete: Board?
    @State private var showsShortcuts = false
    /// The ⌘K palette's items while it's open.
    @State private var paletteItems: [PaletteItem]?
    /// Asked of a Canvas by the palette; the Canvas clears it once done.
    @State private var canvasRequest: CanvasRequest?
    /// A Reference the palette asked the Library to open.
    @State private var libraryReference: Reference?

    var body: some View {
        withDialogs(withPanels(splitView))
        #if DEBUG
        .task { await applyLaunchRoute() }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item.selection)
                }
                boardsSection
                canvasesSection
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
        }
        .tint(.primary)
    }

    /// Menu actions, the ⌘K palette, the shortcut sheet and undo wiring.
    private func withPanels(_ content: some View) -> some View {
        content
            .focusedSceneValue(\.canvasActions, CanvasActions(newCanvas: newCanvas, newBoard: newBoard))
            .focusedSceneValue(\.showShortcuts, ShortcutsAction { showsShortcuts = true })
            .focusedSceneValue(\.showPalette, PaletteAction(show: showPalette))
            #if DEBUG
            .focusedSceneValue(\.debugActions, DebugActions(makeStressCanvas: makeStressCanvas))
            #endif
            .overlay(alignment: .top) {
                if let items = paletteItems {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.06)
                            .ignoresSafeArea()
                            .onTapGesture { paletteItems = nil }
                        CommandPalette(items: items) { paletteItems = nil }
                            .padding(.top, 72)
                    }
                }
            }
            .sheet(isPresented: $showsShortcuts) {
                ShortcutHelpView()
            }
            // Edit › Undo / Redo reach SwiftData through the window's undo manager.
            .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) {
                context.undoManager = undoManager
            }
    }

    /// Rename and delete prompts for Canvases and Boards.
    private func withDialogs(_ content: some View) -> some View {
        content
            .alert("Rename Canvas", isPresented: isRenaming) {
                TextField("Title", text: $draftTitle)
                Button("Rename") {
                    renaming?.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    CanvasGraph.touch(renaming)
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Name the Board", isPresented: isRenamingBoard) {
                TextField("Name", text: $draftTitle)
                Button("Save") {
                    renamingBoard?.name = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete “\(pendingBoardDelete?.displayName ?? "")”?",
                isPresented: isConfirmingBoardDelete,
                presenting: pendingBoardDelete
            ) { board in
                Button("Delete Board", role: .destructive) { delete(board) }
            } message: { _ in
                Text("Its references stay in the Library.")
            }
            .confirmationDialog(
                "Delete “\(pendingDelete?.displayTitle ?? "")”?",
                isPresented: isConfirmingDelete,
                presenting: pendingDelete
            ) { canvas in
                Button("Delete Canvas", role: .destructive) { delete(canvas) }
            } message: { _ in
                Text("Its Ideas, notes and links are deleted. References stay in the Library.")
            }
    }

    private var boardsSection: some View {
        Section {
            ForEach(boards) { board in
                boardRow(board)
            }
        } header: {
            SidebarHeader(title: "Boards", add: "New Board", shortcut: ShortcutCatalog.newBoard, action: newBoard)
        }
    }

    private func boardRow(_ board: Board) -> some View {
        Label(board.displayName, systemImage: "rectangle.stack")
            .tag(SidebarSelection.board(board.id))
            .contextMenu {
                Button("Rename…") {
                    draftTitle = board.name
                    renamingBoard = board
                }
                Divider()
                Button("Delete…", role: .destructive) { pendingBoardDelete = board }
            }
            // References dragged from the Library (or a Board) land on this Board.
            .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                add(items, to: board)
            }
    }

    private var canvasesSection: some View {
        Section {
            ForEach(canvases) { canvas in
                canvasRow(canvas)
            }
        } header: {
            SidebarHeader(title: "Canvases", add: "New Canvas", shortcut: ShortcutCatalog.newCanvas, action: newCanvas)
        }
    }

    private func canvasRow(_ canvas: Canvas) -> some View {
        Label(canvas.displayTitle, systemImage: "point.3.connected.trianglepath.dotted")
            .tag(SidebarSelection.canvas(canvas.id))
            .contextMenu {
                Button("Rename…") {
                    draftTitle = canvas.title
                    renaming = canvas
                }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = canvas }
            }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .inbox:
            InboxView()
        case .boards:
            BoardsView { board in selection = .board(board.id) }
        case .board(let id):
            if let board = boards.first(where: { $0.id == id }) {
                NavigationStack {
                    ReferenceCollectionView(board: board)
                        .navigationDestination(for: Reference.self) { reference in
                            ReferenceDetailView(reference: reference)
                        }
                }
                .id(board.id)
            } else {
                EmptyState(title: "Board", message: "This board was deleted.")
            }
        case .canvasGraph:
            CanvasGraphOverview { canvas in selection = .canvas(canvas.id) }
        case .canvas(let id):
            if let canvas = canvases.first(where: { $0.id == id }) {
                CanvasMapView(canvas: canvas, request: $canvasRequest)
                    .id(canvas.id)
            } else {
                EmptyState(title: "Canvas", message: "This canvas was deleted.")
            }
        case .library, nil:
            LibraryView(pending: $libraryReference)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding { renaming != nil } set: { if !$0 { renaming = nil } }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private var isRenamingBoard: Binding<Bool> {
        Binding { renamingBoard != nil } set: { if !$0 { renamingBoard = nil } }
    }

    private var isConfirmingBoardDelete: Binding<Bool> {
        Binding { pendingBoardDelete != nil } set: { if !$0 { pendingBoardDelete = nil } }
    }

    /// ⇧⌘N: a new Board, selected, with its name asked for.
    private func newBoard() {
        let board = Board.make(name: "", in: context)
        try? context.save()
        selection = .board(board.id)
        draftTitle = ""
        renamingBoard = board
    }

    private func delete(_ board: Board) {
        if selection == .board(board.id) { selection = .boards }
        Board.delete(board, in: context)
        try? context.save()
    }

    /// Library tiles dragged onto a Board in the sidebar.
    private func add(_ payloads: [String], to board: Board) -> Bool {
        let ids = Set(payloads.compactMap(LibraryDrag.referenceID(in:)))
        let dropped = references.filter { ids.contains($0.id) }
        guard !dropped.isEmpty else { return false }
        board.add(dropped)
        try? context.save()
        return true
    }

    /// ⌘K. Built now, while the Canvas or Library still has the keyboard, so their actions
    /// (like Import) are included.
    private func showPalette() {
        var openCanvasID: UUID?
        if case let .canvas(id) = selection { openCanvasID = id }
        paletteItems = PaletteItems.make(PaletteItems.Sources(
            canvases: canvases,
            references: references,
            openCanvasID: openCanvasID,
            openCanvas: { canvas in selection = .canvas(canvas.id) },
            request: { canvasID, action in
                selection = .canvas(canvasID)
                canvasRequest = CanvasRequest(canvasID: canvasID, action: action)
            },
            openReference: { reference in
                selection = .library
                libraryReference = reference
            },
            newCanvas: newCanvas,
            importFiles: importFiles?.run,
            showShortcuts: { showsShortcuts = true },
            showCanvasGraph: { selection = .canvasGraph }
        ))
    }

    private func newCanvas() {
        let new = CanvasGraph.makeCanvas(title: "", in: context)
        try? context.save()
        selection = .canvas(new.canvas.id)
    }

    private func delete(_ canvas: Canvas) {
        if selection == .canvas(canvas.id) { selection = .library }
        CanvasGraph.deleteCanvas(canvas, in: context)
        try? context.save()
    }

    #if DEBUG
    /// Debug › Generate 500-Node Canvas.
    private func makeStressCanvas() {
        let canvas = CanvasStress.make(in: context, references: Array(references.prefix(12)))
        selection = .canvas(canvas.id)
    }

    /// Opens the screen named by `-MotiffOpen`, then saves a snapshot if `-MotiffSnapshot` asks.
    private func applyLaunchRoute() async {
        guard let route = DebugLaunchRoute.open else { return }
        // Seeding also runs at launch; give it a moment so a seeded Canvas can be found.
        try? await Task.sleep(for: .seconds(1.5))
        if DebugLaunchRoute.makesStressCanvas {
            let references = (try? context.fetch(FetchDescriptor<Reference>())) ?? []
            CanvasStress.make(in: context, references: Array(references.prefix(12)))
        }
        let all = (try? context.fetch(FetchDescriptor<Canvas>())) ?? []
        let allBoards = (try? context.fetch(FetchDescriptor<Board>())) ?? []
        selection = DebugLaunchRoute.selection(for: route, canvases: all, boards: allBoards)
        showsShortcuts = DebugLaunchRoute.showsShortcuts
        if let name = DebugLaunchRoute.snapshotName {
            try? await Task.sleep(for: .seconds(DebugLaunchRoute.settleSeconds))
            DebugLaunchRoute.writeSnapshot(named: name)
        }
    }
    #endif
}

/// A sidebar section's title with its + button.
private struct SidebarHeader: View {
    let title: String
    let add: String
    let shortcut: Shortcut
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(add, systemImage: "plus", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("\(add) (\(shortcut.keys))")
        }
    }
}

#Preview {
    RootView()
}
#endif
