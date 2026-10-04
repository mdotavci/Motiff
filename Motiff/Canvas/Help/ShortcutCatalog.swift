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
    static let undo = Shortcut("Undo", "z", .command)
    static let redo = Shortcut("Redo", "z", [.command, .shift])

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

    static let sections: [ShortcutSection] = [
        ShortcutSection(title: "Motiff", items: [newCanvas, undo, redo, showShortcuts]),
        ShortcutSection(title: "Library", items: [largerThumbnails, smallerThumbnails, defaultThumbnails]),
        ShortcutSection(title: "Canvas", items: [zoomIn, zoomOut, fit, pan, zoomAtPointer]),
        ShortcutSection(title: "Canvas editing", items: [
            addNote, addSubIdea, edit, editByClick, finishEditing, cancelEditing, newLine,
            delete, deleteBranch, select, extendSelection, deselect, move, moveAlone, inspector,
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
