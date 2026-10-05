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

/// What the sidebar has selected: a fixed section, or one Canvas file.
enum SidebarSelection: Hashable {
    case inbox, library, boards, canvasGraph
    case canvas(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Canvas.createdAt) private var canvases: [Canvas]

    @State private var selection: SidebarSelection? = .library
    @State private var renaming: Canvas?
    @State private var draftTitle = ""
    @State private var pendingDelete: Canvas?
    @State private var showsShortcuts = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item.selection)
                }
                Section {
                    ForEach(canvases) { canvas in
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
                } header: {
                    HStack {
                        Text("Canvases")
                        Spacer()
                        Button("New Canvas", systemImage: "plus", action: newCanvas)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("New Canvas (\(ShortcutCatalog.newCanvas.keys))")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
        }
        .tint(.primary)
        .focusedSceneValue(\.canvasActions, CanvasActions(newCanvas: newCanvas))
        .focusedSceneValue(\.showShortcuts, ShortcutsAction { showsShortcuts = true })
        .sheet(isPresented: $showsShortcuts) {
            ShortcutHelpView()
        }
        // Edit › Undo / Redo reach SwiftData through the window's undo manager.
        .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) {
            context.undoManager = undoManager
        }
        .alert("Rename Canvas", isPresented: isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Rename") {
                renaming?.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                CanvasGraph.touch(renaming)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
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
        #if DEBUG
        .task { await applyLaunchRoute() }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .inbox:
            InboxView()
        case .boards:
            BoardsView()
        case .canvasGraph:
            CanvasGraphOverview { canvas in selection = .canvas(canvas.id) }
        case .canvas(let id):
            if let canvas = canvases.first(where: { $0.id == id }) {
                CanvasMapView(canvas: canvas)
                    .id(canvas.id)
            } else {
                EmptyState(title: "Canvas", message: "This canvas was deleted.")
            }
        case .library, nil:
            LibraryView()
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding { renaming != nil } set: { if !$0 { renaming = nil } }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
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
    /// Opens the screen named by `-MotiffOpen`, then saves a snapshot if `-MotiffSnapshot` asks.
    private func applyLaunchRoute() async {
        guard let route = DebugLaunchRoute.open else { return }
        // Seeding also runs at launch; give it a moment so a seeded Canvas can be found.
        try? await Task.sleep(for: .seconds(1.5))
        let all = (try? context.fetch(FetchDescriptor<Canvas>())) ?? []
        selection = DebugLaunchRoute.selection(for: route, canvases: all)
        showsShortcuts = DebugLaunchRoute.showsShortcuts
        if let name = DebugLaunchRoute.snapshotName {
            try? await Task.sleep(for: .seconds(DebugLaunchRoute.settleSeconds))
            DebugLaunchRoute.writeSnapshot(named: name)
        }
    }
    #endif
}

#Preview {
    RootView()
}
#endif
