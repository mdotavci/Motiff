import Foundation

/// Everything the ⌘K palette offers, built when it opens: actions (with the open Canvas's own),
/// every Canvas, every node on every Canvas, and the Library's References.
@MainActor
enum PaletteItems {
    struct Sources {
        var canvases: [Canvas]
        var references: [Reference]
        /// The Canvas on screen, if one is.
        var openCanvasID: UUID?
        var openCanvas: @MainActor (Canvas) -> Void
        /// Opens that Canvas if needed, then asks it to do something.
        var request: @MainActor (UUID, CanvasRequest.Action) -> Void
        var openReference: @MainActor (Reference) -> Void
        var newCanvas: @MainActor () -> Void
        var importFiles: (@MainActor () -> Void)?
        var showShortcuts: @MainActor () -> Void
        var showCanvasGraph: @MainActor () -> Void
    }

    static func make(_ sources: Sources) -> [PaletteItem] {
        var items: [PaletteItem] = []

        func action(_ shortcut: Shortcut, _ icon: String, title: String? = nil, run: @escaping @MainActor () -> Void) {
            items.append(PaletteItem(
                id: "action:\(shortcut.id)", kind: .action, title: title ?? shortcut.title,
                subtitle: "Action", systemImage: icon, keys: shortcut.keys, run: run
            ))
        }

        action(ShortcutCatalog.newCanvas, "plus", run: sources.newCanvas)
        if let importFiles = sources.importFiles {
            action(ShortcutCatalog.importFiles, "square.and.arrow.down", run: importFiles)
        }
        action(ShortcutCatalog.showShortcuts, "keyboard", run: sources.showShortcuts)
        items.append(PaletteItem(
            id: "action:canvas-graph", kind: .action, title: "Board Graph", subtitle: "Action",
            systemImage: "point.3.filled.connected.trianglepath.dotted", run: sources.showCanvasGraph
        ))

        if let open = sources.openCanvasID {
            let request = sources.request
            for mode in CanvasViewMode.allCases {
                action(ShortcutCatalog.view(mode), mode.systemImage, title: "Show \(mode.label)") { request(open, .view(mode)) }
            }
            action(ShortcutCatalog.addNote, "note.text.badge.plus") { request(open, .addNote) }
            action(ShortcutCatalog.addSubIdea, "circle.badge.plus") { request(open, .addSubIdea) }
            action(ShortcutCatalog.find, "magnifyingglass") { request(open, .find) }
            action(ShortcutCatalog.inspector, "sidebar.right", title: "Show or Hide Inspector") { request(open, .toggleInspector) }
            action(ShortcutCatalog.linkMode, "link") { request(open, .toggleLinkMode) }
            action(ShortcutCatalog.minimap, "map") { request(open, .toggleMinimap) }
        }

        for canvas in sources.canvases {
            items.append(PaletteItem(
                id: "canvas:\(canvas.id)", kind: .canvas, title: canvas.displayTitle, subtitle: "Board",
                systemImage: "rectangle.3.group"
            ) { sources.openCanvas(canvas) })
        }

        var onOpenCanvas: Set<UUID> = []
        for canvas in sources.canvases {
            for node in canvas.nodes where !node.isDeleted && !node.isRoot && !node.isLine {
                if canvas.id == sources.openCanvasID, let reference = node.reference { onOpenCanvas.insert(reference.id) }
                let canvasID = canvas.id
                let nodeID = node.id
                items.append(PaletteItem(
                    id: "node:\(node.id)", kind: .node, title: node.displayTitle,
                    subtitle: "\(node.kind.label) · \(canvas.displayTitle)", systemImage: icon(for: node.kind)
                ) { sources.request(canvasID, .focus(nodeID)) })
            }
        }

        for reference in sources.references where !onOpenCanvas.contains(reference.id) {
            items.append(PaletteItem(
                id: "reference:\(reference.id)", kind: .reference, title: reference.caption,
                subtitle: "\(reference.origin.label) · Library", systemImage: "photo"
            ) { sources.openReference(reference) })
        }
        return items
    }

    private static func icon(for kind: NodeKind) -> String {
        switch kind {
        case .idea: "circle.fill"
        case .reference: "photo"
        case .prompt: "text.quote"
        case .note: "text.alignleft"
        case .link: "link"
        case .text: "textformat"
        case .sticky: "note"
        case .shape: "square.on.circle"
        }
    }
}
