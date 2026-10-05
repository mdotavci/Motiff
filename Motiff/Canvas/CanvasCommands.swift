import SwiftUI

/// Canvas actions the menu bar can reach in the focused window.
struct CanvasActions {
    var newCanvas: @MainActor () -> Void
}

/// Zoom for the Canvas in the focused window. While it's set, View › Zoom In / Zoom Out /
/// Fit to Screen (⌘+ ⌘− ⌘0) drive the Map instead of the Library's thumbnail size.
struct CanvasZoomActions {
    var zoomIn: @MainActor () -> Void
    var zoomOut: @MainActor () -> Void
    var fit: @MainActor () -> Void
}

/// Editing on the Canvas in the focused window, for the Canvas menu.
struct CanvasEditActions {
    var hasSelection: Bool
    var showsInspector: Bool
    var addNote: @MainActor () -> Void
    var addSubIdea: @MainActor () -> Void
    var edit: @MainActor () -> Void
    var delete: @MainActor () -> Void
    var deleteBranch: @MainActor () -> Void
    var toggleInspector: @MainActor () -> Void
    var linkMode: Bool
    var toggleLinkMode: @MainActor () -> Void
    var canOpen: Bool
    var open: @MainActor () -> Void
    var canCopyPrompt: Bool
    var copyPrompt: @MainActor () -> Void
    var viewMode: CanvasViewMode
    var setViewMode: @MainActor (CanvasViewMode) -> Void
}

/// File › Import… (⌘O) in the focused Library or Canvas.
struct ImportAction {
    var run: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var importFiles: ImportAction?
    @Entry var canvasActions: CanvasActions?
    @Entry var canvasZoom: CanvasZoomActions?
    @Entry var canvasEditing: CanvasEditActions?
}

#if os(macOS)
/// File › New Canvas (⌘N), which replaces New Window (Motiff is a single-window app), Import…,
/// the Canvas menu, and Help › Keyboard Shortcuts (⌘/).
///
/// Tab, Return, Space, L, ⌫, Esc and the arrows are handled by the Map itself, not here: as menu shortcuts they'd
/// take those keys away from every text field. Their menu items show no key; the help sheet
/// lists them.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasActions) private var actions
    @FocusedValue(\.canvasEditing) private var editing
    @FocusedValue(\.showShortcuts) private var shortcuts
    @FocusedValue(\.importFiles) private var importFiles

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(ShortcutCatalog.newCanvas.title) { actions?.newCanvas() }
                .shortcut(ShortcutCatalog.newCanvas)
                .disabled(actions == nil)
            Button(ShortcutCatalog.importFiles.title) { importFiles?.run() }
                .shortcut(ShortcutCatalog.importFiles)
                .disabled(importFiles == nil)
        }

        CommandMenu("Canvas") {
            ForEach(CanvasViewMode.allCases) { mode in
                Toggle(mode.label, isOn: Binding(
                    get: { editing?.viewMode == mode },
                    set: { if $0 { editing?.setViewMode(mode) } }
                ))
                .shortcut(ShortcutCatalog.view(mode))
                .disabled(editing == nil)
            }
            Divider()
            Button(ShortcutCatalog.addNote.title) { editing?.addNote() }
                .disabled(editing == nil)
            Button(ShortcutCatalog.addSubIdea.title) { editing?.addSubIdea() }
                .shortcut(ShortcutCatalog.addSubIdea)
                .disabled(editing == nil)
            Divider()
            Button(ShortcutCatalog.openDetail.title) { editing?.open() }
                .disabled(editing?.canOpen != true)
            Button(ShortcutCatalog.copyPrompt.title) { editing?.copyPrompt() }
                .shortcut(ShortcutCatalog.copyPrompt)
                .disabled(editing?.canCopyPrompt != true)
            Button(ShortcutCatalog.edit.title) { editing?.edit() }
                .disabled(editing?.hasSelection != true)
            Button("Delete") { editing?.delete() }
                .disabled(editing?.hasSelection != true)
            Button("Delete With Everything Under It") { editing?.deleteBranch() }
                .disabled(editing?.hasSelection != true)
            Divider()
            Button(editing?.linkMode == true ? "Stop Link Mode" : ShortcutCatalog.linkMode.title) {
                editing?.toggleLinkMode()
            }
            .disabled(editing == nil)
            Button(editing?.showsInspector == true ? "Hide Inspector" : "Show Inspector") {
                editing?.toggleInspector()
            }
            .shortcut(ShortcutCatalog.inspector)
            .disabled(editing == nil)
        }

        CommandGroup(replacing: .help) {
            Button(ShortcutCatalog.showShortcuts.title) { shortcuts?.show() }
                .shortcut(ShortcutCatalog.showShortcuts)
                .disabled(shortcuts == nil)
        }
    }
}
#endif
