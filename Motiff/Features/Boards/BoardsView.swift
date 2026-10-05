import SwiftData
import SwiftUI

/// Every Board as a tile: a few of its pictures, its name and how many it holds. + makes one.
/// On the Mac a tile opens the Board in the sidebar (`open`); on iPhone it pushes the Board.
struct BoardsView: View {
    /// Mac: select this Board in the sidebar. Nil on iPhone, where tiles navigate.
    var open: ((Board) -> Void)?

    @Environment(\.modelContext) private var context
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @State private var renaming: Board?
    @State private var draftName = ""
    @State private var pendingDelete: Board?

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 180), spacing: Theme.gutter)] }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationDestination(for: Board.self) { board in
                    ReferenceCollectionView(board: board)
                }
                .navigationDestination(for: Reference.self) { reference in
                    ReferenceDetailView(reference: reference)
                }
        }
        #else
        content
        #endif
    }

    private var content: some View {
        Group {
            if boards.isEmpty {
                EmptyState(title: "Boards", message: "A board is a wall of references for one project or mood. Make one with +, then add images to it.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.gutter) {
                        ForEach(boards) { board in
                            tile(for: board)
                                .contextMenu {
                                    Button("Rename…", systemImage: "pencil") {
                                        draftName = board.name
                                        renaming = board
                                    }
                                    Divider()
                                    Button("Delete…", systemImage: "trash", role: .destructive) { pendingDelete = board }
                                }
                        }
                    }
                    .padding(Theme.gutter)
                }
            }
        }
        .navigationTitle("Boards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Board", systemImage: "plus", action: newBoard)
                    .help("New Board (\(ShortcutCatalog.newBoard.keys))")
            }
        }
        .alert("Name the Board", isPresented: isRenaming) {
            TextField("Name", text: $draftName)
            Button("Save") {
                renaming?.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.displayName ?? "")”?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { board in
            Button("Delete Board", role: .destructive) {
                Board.delete(board, in: context)
                try? context.save()
            }
        } message: { _ in
            Text("Its references stay in the Library.")
        }
    }

    @ViewBuilder
    private func tile(for board: Board) -> some View {
        if let open {
            Button { open(board) } label: { BoardTile(board: board) }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: board) { BoardTile(board: board) }
                .buttonStyle(.plain)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding { renaming != nil } set: { if !$0 { renaming = nil } }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private func newBoard() {
        let board = Board.make(name: "", in: context)
        try? context.save()
        draftName = ""
        renaming = board
    }
}

/// Up to four of the Board's pictures in a square, its name and count below.
private struct BoardTile: View {
    let board: Board

    var body: some View {
        let covers = Array(board.sortedReferences.prefix(4))
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Color.primary.opacity(0.06)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if covers.indices.contains(index) {
                                let reference = covers[index]
                                if reference.hasMedia {
                                    ThumbnailImage(url: reference.mediaURL, pointSize: 120)
                                } else {
                                    TypographicCover(text: reference.copyablePrompt ?? "")
                                }
                            }
                        }
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(board.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(board.references.count == 1 ? "1 reference" : "\(board.references.count) references")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
