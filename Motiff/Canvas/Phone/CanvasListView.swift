#if os(iOS)
import SwiftData
import SwiftUI

/// The iPhone's Boards tab: every board, newest last, as on the Mac's sidebar. Tap one to open
/// it on the Map; swipe for Rename and Delete; + makes a new one.
struct CanvasListView: View {
    /// The open board, if any: a path of one, so the launch route can open it too.
    @Binding var path: [UUID]

    @Environment(\.modelContext) private var context
    @Query(sort: \Canvas.createdAt) private var canvases: [Canvas]

    @State private var renaming: Canvas?
    @State private var draftTitle = ""
    @State private var pendingDelete: Canvas?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(canvases) { canvas in
                    NavigationLink(value: canvas.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(canvas.displayTitle)
                            Text(canvas.nodes.count == 1 ? "1 item" : "\(canvas.nodes.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = canvas }
                        Button("Rename", systemImage: "pencil") {
                            draftTitle = canvas.title
                            renaming = canvas
                        }
                    }
                }
            }
            .overlay {
                if canvases.isEmpty {
                    EmptyState(title: "Boards", message: "Tap + to start a board: pictures, prompts and notes for one idea, connected however you like.")
                        .padding(Theme.gutter)
                }
            }
            .navigationTitle("Boards")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Board", systemImage: "plus", action: newCanvas)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let canvas = canvases.first(where: { $0.id == id }) {
                    CanvasMapView(canvas: canvas)
                        .id(canvas.id)
                } else {
                    EmptyState(title: "Board", message: "This board was deleted.")
                }
            }
        }
        .alert("Rename Board", isPresented: isRenaming) {
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
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { canvas in
            Button("Delete Board", role: .destructive) { delete(canvas) }
        } message: { _ in
            Text("Everything on it is deleted. Its pictures and prompts stay in the Library.")
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
        path = [new.canvas.id]
    }

    private func delete(_ canvas: Canvas) {
        path.removeAll { $0 == canvas.id }
        CanvasGraph.deleteCanvas(canvas, in: context)
        try? context.save()
    }
}
#endif
