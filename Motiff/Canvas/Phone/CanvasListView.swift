#if os(iOS)
import SwiftData
import SwiftUI

/// The iPhone's Canvases tab: every Canvas, newest last, as on the Mac's sidebar. Tap one to open
/// it in the Outline (the Map is one tap away); swipe for Rename and Delete; + makes a new one.
struct CanvasListView: View {
    /// The open Canvas, if any: a path of one, so the launch route can open it too.
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
                            Text("\(canvas.nodes.count) nodes")
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
                    EmptyState(title: "Canvases", message: "Tap + to start a Canvas: an Idea in the middle, with references, prompts and notes around it.")
                        .padding(Theme.gutter)
                }
            }
            .navigationTitle("Canvases")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Canvas", systemImage: "plus", action: newCanvas)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let canvas = canvases.first(where: { $0.id == id }) {
                    CanvasMapView(canvas: canvas, viewMode: .outline)
                        .id(canvas.id)
                } else {
                    EmptyState(title: "Canvas", message: "This canvas was deleted.")
                }
            }
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
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { canvas in
            Button("Delete Canvas", role: .destructive) { delete(canvas) }
        } message: { _ in
            Text("Its Ideas, notes and links are deleted. References stay in the Library.")
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
