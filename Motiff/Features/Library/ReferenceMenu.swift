import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Context menu for a Reference tile: copy, boards, reveal, delete.
struct ReferenceMenu: View {
    @Environment(\.modelContext) private var context
    let reference: Reference
    let boards: [Board]
    let onDelete: () -> Void

    var body: some View {
        Button("Copy Prompt", systemImage: "text.quote") {
            if let prompt = reference.copyablePrompt { Pasteboard.copy(prompt) }
        }
        .disabled(reference.copyablePrompt == nil)

        Button("Copy Image", systemImage: "doc.on.doc") {
            Pasteboard.copyImage(at: reference.mediaURL)
        }
        .disabled(!reference.hasMedia)

        Menu("Boards", systemImage: "rectangle.stack") {
            ForEach(boards) { board in
                Toggle(board.displayName, isOn: membership(in: board))
            }
            if !boards.isEmpty { Divider() }
            Button("New Board With This") {
                Board.make(name: "New board", in: context).add([reference])
                try? context.save()
            }
        }

        #if os(macOS)
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([reference.mediaURL])
        }
        .disabled(!reference.hasMedia)
        #endif

        Divider()

        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
    }

    private func membership(in board: Board) -> Binding<Bool> {
        Binding {
            reference.boards.contains { $0.id == board.id }
        } set: { isOn in
            if isOn {
                reference.boards.append(board)
            } else {
                reference.boards.removeAll { $0.id == board.id }
            }
        }
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copyImage(at url: URL) {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        UIPasteboard.general.image = image
        #endif
    }
}
