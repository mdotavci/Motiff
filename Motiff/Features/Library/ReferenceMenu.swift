import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Context menu for a Reference tile: copy, boards, reveal, delete.
struct ReferenceMenu: View {
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

        if !boards.isEmpty {
            Menu("Boards") {
                ForEach(boards) { board in
                    Toggle(board.name, isOn: membership(in: board))
                }
            }
        }

        #if os(macOS)
        Button("Show in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([reference.mediaURL])
        }
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
