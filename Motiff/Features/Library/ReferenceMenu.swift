import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Context menu for a Reference tile: copy, add to a board, reveal, delete.
struct ReferenceMenu: View {
    @Environment(\.modelContext) private var context
    let reference: Reference
    let boards: [Canvas]
    let onDelete: () -> Void

    var body: some View {
        Button("Copy Prompt", systemImage: "text.quote") {
            if let prompt = reference.promptToCopy { Pasteboard.copy(prompt) }
        }
        .disabled(reference.copyablePrompt == nil)

        Button("Copy Image", systemImage: "doc.on.doc") {
            Pasteboard.copyImage(at: reference.mediaURL)
        }
        .disabled(!reference.hasMedia)

        Menu("Add to Board", systemImage: "rectangle.3.group") {
            ForEach(boards) { board in
                Toggle(board.displayTitle, isOn: isOn(board))
            }
            if !boards.isEmpty { Divider() }
            Button("New Board With This") {
                let new = CanvasGraph.makeCanvas(title: "New board", in: context)
                CanvasGraph.addReferences([reference], to: new.canvas, in: context)
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

    /// On: it has a card on that board. Turning it on adds one beside what's there; off takes
    /// its cards off (it stays in the Library).
    private func isOn(_ board: Canvas) -> Binding<Bool> {
        Binding {
            !CanvasGraph.cards(of: reference, on: board).isEmpty
        } set: { isOn in
            if isOn {
                CanvasGraph.addReferences([reference], to: board, in: context)
            } else {
                CanvasGraph.delete(CanvasGraph.cards(of: reference, on: board), branch: false, in: context)
            }
            try? context.save()
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
