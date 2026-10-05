import SwiftUI

/// One thing you can do from the keyboard (or with the pointer), as the help sheet lists it.
/// Menu items take their key from here too, so the sheet and the menus can't disagree.
struct Shortcut: Identifiable {
    let title: String
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    /// For pointer actions, what to do: "⇧-click", "Drag".
    let pointer: String?

    var id: String { title + keys }

    init(_ title: String, _ key: KeyEquivalent, _ modifiers: EventModifiers = []) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.pointer = nil
    }

    init(_ title: String, pointer: String) {
        self.title = title
        self.key = nil
        self.modifiers = []
        self.pointer = pointer
    }

    /// "⌥⌘I", "⇥", "⇧-click".
    var keys: String {
        if let pointer { return pointer }
        guard let key else { return "" }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.name(of: key)
    }

    private static func name(of key: KeyEquivalent) -> String {
        switch key {
        case .return: "↩"
        case .delete: "⌫"
        case .deleteForward: "⌦"
        case .tab: "⇥"
        case .escape: "esc"
        case .space: "Space"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case "-": "−"
        default: String(key.character).uppercased()
        }
    }
}

struct ShortcutSection: Identifiable {
    let title: String
    let items: [Shortcut]
    var id: String { title }
}

/// Every shortcut in Motiff. Add one here when an action arrives; the help sheet (⌘/) lists them.
@MainActor
enum ShortcutCatalog {
    // MARK: App

    static let newCanvas = Shortcut("New Canvas", "n", .command)
    static let showShortcuts = Shortcut("Keyboard Shortcuts", "/", .command)
    static let goTo = Shortcut("Go To…", "k", .command)
    static let undo = Shortcut("Undo", "z", .command)
    static let redo = Shortcut("Redo", "z", [.command, .shift])

    // MARK: Bringing things in

    static let importFiles = Shortcut("Import Images or Videos…", "o", .command)
    static let paste = Shortcut("Paste Images, Links or Prompts", "v", .command)
    static let dropIn = Shortcut("Bring In Files, Images or Links", pointer: "Drag them in from Finder or a browser")
    static let dropOnIdea = Shortcut("Attach to an Idea", pointer: "Drop onto the Idea")

    // MARK: Library

    static let largerThumbnails = Shortcut("Larger Thumbnails", "+", .command)
    static let smallerThumbnails = Shortcut("Smaller Thumbnails", "-", .command)
    static let defaultThumbnails = Shortcut("Default Thumbnail Size", "0", .command)

    // MARK: Canvas: looking around

    static let zoomIn = Shortcut("Zoom In", "+", .command)
    static let zoomOut = Shortcut("Zoom Out", "-", .command)
    static let fit = Shortcut("Fit to Screen", "0", .command)
    static let pan = Shortcut("Pan", pointer: "Scroll, or drag the background")
    static let zoomAtPointer = Shortcut("Zoom at the pointer", pointer: "Pinch, or ⌘-scroll")

    // MARK: Canvas: editing

    static let addNote = Shortcut("Add Note", .tab)
    static let addSubIdea = Shortcut("Add Sub-Idea", .return, .command)
    static let edit = Shortcut("Edit Text", .return)
    static let editByClick = Shortcut("Edit Text", pointer: "Double-click")
    static let finishEditing = Shortcut("Finish Editing", .return)
    static let cancelEditing = Shortcut("Cancel Editing", .escape)
    static let newLine = Shortcut("New Line in a Note", .return, .option)
    static let delete = Shortcut("Delete (an Idea’s cards move up)", .delete)
    static let deleteBranch = Shortcut("Delete With Everything Under It", .delete, .command)
    static let select = Shortcut("Select", pointer: "Click")
    static let extendSelection = Shortcut("Add to Selection", pointer: "⇧-click")
    static let deselect = Shortcut("Deselect", .escape)
    static let move = Shortcut("Move (an Idea brings its cards)", pointer: "Drag")
    static let moveAlone = Shortcut("Move Just the Idea", pointer: "⌥-drag")
    static let inspector = Shortcut("Show Inspector", "i", [.command, .option])
    static let nodeMenu = Shortcut("Everything You Can Do to a Node", pointer: "Right-click it (long-press on iPhone)")

    // MARK: Canvas: finding

    static let find = Shortcut("Find…", "f", .command)
    static let findNext = Shortcut("Find Next", "g", .command)
    static let findPrevious = Shortcut("Find Previous", "g", [.command, .shift])
    static let closeFind = Shortcut("Close Find", .escape)
    static let minimap = Shortcut("Show or Hide the Minimap", "m", [.command, .option])
    static let minimapMove = Shortcut("Look Somewhere Else", pointer: "Click or drag in the minimap")

    // MARK: Canvas: views

    static let mapView = Shortcut("Map", "1", .command)
    static let outlineView = Shortcut("Outline", "2", .command)
    static let graphView = Shortcut("Graph", "3", .command)

    static func view(_ mode: CanvasViewMode) -> Shortcut {
        switch mode {
        case .map: mapView
        case .outline: outlineView
        case .graph: graphView
        }
    }

    static let outlineStep = Shortcut("Outline: Previous or Next Row", pointer: "↑ ↓")
    static let outlineFold = Shortcut("Outline: Fold or Unfold", pointer: "← →")
    static let outlineIndent = Shortcut("Outline: Put Under the Row Above", .tab)
    static let outlineOutdent = Shortcut("Outline: Move Up a Level", .tab, .shift)
    static let outlineMoveUp = Shortcut("Outline: Move Up", .upArrow, [.command, .option])
    static let outlineMoveDown = Shortcut("Outline: Move Down", .downArrow, [.command, .option])
    static let graphShowOnMap = Shortcut("Graph: Show on the Map", .return)
    static let graphOpen = Shortcut("Graph: Open Full Size", pointer: "Double-click a dot")

    // MARK: Canvas: categories

    static let assignCategory = Shortcut("Give the Selection a Category", pointer: "1 to 9, in legend order")
    static let noCategory = Shortcut("No Category", "0")
    static let filterCategory = Shortcut("Show Only a Category or Purpose", pointer: "Click it in the legend")
    static let filterMore = Shortcut("Show More Than One", pointer: "⇧-click in the legend")
    static let clearFilter = Shortcut("Show Everything Again", .escape)

    // MARK: Canvas: full size

    static let openDetail = Shortcut("Open Full Size", .space)
    static let openByDoubleClick = Shortcut("Open a Reference or Prompt", pointer: "Double-click it")
    static let closeDetail = Shortcut("Back to the Canvas", .escape)
    static let previousSibling = Shortcut("Previous at the Same Level", .leftArrow)
    static let nextSibling = Shortcut("Next at the Same Level", .rightArrow)
    static let copyPrompt = Shortcut("Copy Prompt", "c", [.command, .shift])

    // MARK: Canvas: tools

    static let selectTool = Shortcut("Select Tool", "v")
    static let handTool = Shortcut("Hand Tool: Drag to Move Around", "h")
    static let ideaTool = Shortcut("Idea Tool: Click to Place", "o")
    static let noteTool = Shortcut("Note Tool: Click to Place", "n")
    static let textTool = Shortcut("Text Tool: Click to Place", "t")
    static let imageTool = Shortcut("Image Tool: Click Where Images Go", "i")
    static let noteByDoubleClick = Shortcut("New Note Right There", pointer: "Double-click empty space")
    static let libraryPanel = Shortcut("Show Library Panel", "l", [.command, .option])
    static let dragFromLibrary = Shortcut("Put a Reference on the Canvas", pointer: "Drag it from the Library panel")
    static let addFromLibrary = Shortcut("Put It on the Selected Idea", pointer: "Click it in the Library panel")

    static func tool(_ tool: CanvasTool) -> Shortcut {
        switch tool {
        case .select: selectTool
        case .hand: handTool
        case .idea: ideaTool
        case .note: noteTool
        case .text: textTool
        case .image: imageTool
        case .link: linkMode
        }
    }

    // MARK: Canvas: connecting

    static let connect = Shortcut("Put a Node Under Another", pointer: "Drag its handle onto it")
    static let connectLink = Shortcut("Link Two Nodes", pointer: "⌥-drag the handle")
    static let linkMode = Shortcut("Link Mode", "l")
    static let linkModeClicks = Shortcut("Link in Link Mode", pointer: "Click one node, then another")
    static let stopLinkMode = Shortcut("Stop Link Mode", .escape)
    static let lineMenu = Shortcut("Label, Change or Delete a Line", pointer: "Right-click the line")

    static let sections: [ShortcutSection] = [
        ShortcutSection(title: "Motiff", items: [newCanvas, goTo, undo, redo, showShortcuts]),
        ShortcutSection(title: "Bringing things in", items: [importFiles, paste, dropIn, dropOnIdea]),
        ShortcutSection(title: "Library", items: [largerThumbnails, smallerThumbnails, defaultThumbnails]),
        ShortcutSection(title: "Canvas", items: [zoomIn, zoomOut, fit, pan, zoomAtPointer]),
        ShortcutSection(title: "Canvas tools", items: [
            selectTool, handTool, ideaTool, noteTool, textTool, imageTool, noteByDoubleClick,
            libraryPanel, dragFromLibrary, addFromLibrary,
        ]),
        ShortcutSection(title: "Canvas editing", items: [
            addNote, addSubIdea, edit, editByClick, finishEditing, cancelEditing, newLine,
            delete, deleteBranch, select, extendSelection, deselect, move, moveAlone, inspector, nodeMenu,
        ]),
        ShortcutSection(title: "Canvas finding", items: [find, findNext, findPrevious, closeFind, minimap, minimapMove]),
        ShortcutSection(title: "Canvas views", items: [
            mapView, outlineView, graphView, outlineStep, outlineFold, outlineIndent, outlineOutdent,
            outlineMoveUp, outlineMoveDown, graphShowOnMap, graphOpen,
        ]),
        ShortcutSection(title: "Canvas categories", items: [
            assignCategory, noCategory, filterCategory, filterMore, clearFilter,
        ]),
        ShortcutSection(title: "Canvas full size", items: [
            openDetail, openByDoubleClick, closeDetail, previousSibling, nextSibling, copyPrompt,
        ]),
        ShortcutSection(title: "Canvas connections", items: [
            connect, connectLink, linkMode, linkModeClicks, stopLinkMode, lineMenu,
        ]),
    ]
}

extension View {
    /// Gives a menu item or button the shortcut's key, if it has one.
    @ViewBuilder
    func shortcut(_ shortcut: Shortcut) -> some View {
        if let key = shortcut.key {
            keyboardShortcut(key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}

/// Opens the help sheet in the focused window.
struct ShortcutsAction {
    var show: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var showShortcuts: ShortcutsAction?
}
