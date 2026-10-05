import Foundation

/// ⌘F on a Canvas: which nodes contain some text, in Outline order so ⌘G walks them top to bottom.
enum CanvasSearch {
    /// Everything a node says: its title, text, address, and its Reference's prompt, caption
    /// and Why note.
    @MainActor
    static func searchableText(of node: CanvasNode) -> String {
        [
            node.title, node.body, node.urlString,
            node.reference?.copyablePrompt, node.reference?.whyNote, node.reference?.caption,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    @MainActor
    static func matches(in canvas: Canvas, query: String) -> [UUID] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).searchFolded()
        guard !needle.isEmpty else { return [] }
        let byID = Dictionary(canvas.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CanvasOutline.rows(of: canvas, collapsed: []).compactMap { row in
            guard let node = byID[row.id], searchableText(of: node).searchFolded().contains(needle) else { return nil }
            return row.id
        }
    }
}
