import SwiftUI

/// Board actions the menu bar can reach in the focused window.
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
    var addText: @MainActor () -> Void
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
    var find: @MainActor () -> Void
    var findNext: @MainActor () -> Void
    var findPrevious: @MainActor () -> Void
    var canFindNext: Bool
    var showsMinimap: Bool
    var toggleMinimap: @MainActor () -> Void
    var tool: CanvasTool
    var setTool: @MainActor (CanvasTool) -> Void
    var showsLibrary: Bool
    var toggleLibrary: @MainActor () -> Void
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
/// File › New Board (⌘N), which replaces New Window (Motiff is a single-window app), Import…,
/// the Board menu, and Help › Keyboard Shortcuts (⌘/).
///
/// Tab, Return, Space, the tool letters (V H O N T I L), ⌫, Esc and the arrows are handled by the Map itself, not here: as menu shortcuts they'd
/// take those keys away from every text field. Their menu items show no key; the help sheet
/// lists them.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasActions) private var actions
    @FocusedValue(\.canvasEditing) private var editing
    @FocusedValue(\.showShortcuts) private var shortcuts
    @FocusedValue(\.importFiles) private var importFiles
    @FocusedValue(\.showPalette) private var palette
    @FocusedValue(\.debugActions) private var debug
    #if DEBUG
    @AppStorage("debug.fps") private var showsFrameRate = false
    #endif

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(ShortcutCatalog.newCanvas.title) { actions?.newCanvas() }
                .shortcut(ShortcutCatalog.newCanvas)
                .disabled(actions == nil)
            Button(ShortcutCatalog.importFiles.title) { importFiles?.run() }
                .shortcut(ShortcutCatalog.importFiles)
                .disabled(importFiles == nil)
            Divider()
            Button(ShortcutCatalog.goTo.title) { palette?.show() }
                .shortcut(ShortcutCatalog.goTo)
                .disabled(palette == nil)
        }

        CommandMenu("Board") {
            ForEach(CanvasViewMode.allCases) { mode in
                Toggle(mode.label, isOn: Binding(
                    get: { editing?.viewMode == mode },
                    set: { if $0 { editing?.setViewMode(mode) } }
                ))
                .shortcut(ShortcutCatalog.view(mode))
                .disabled(editing == nil)
            }
            Divider()
            Button(ShortcutCatalog.find.title) { editing?.find() }
                .shortcut(ShortcutCatalog.find)
                .disabled(editing == nil)
            Button(ShortcutCatalog.findNext.title) { editing?.findNext() }
                .shortcut(ShortcutCatalog.findNext)
                .disabled(editing?.canFindNext != true)
            Button(ShortcutCatalog.findPrevious.title) { editing?.findPrevious() }
                .shortcut(ShortcutCatalog.findPrevious)
                .disabled(editing?.canFindNext != true)
            Button(editing?.showsMinimap == true ? "Hide Minimap" : "Show Minimap") { editing?.toggleMinimap() }
                .shortcut(ShortcutCatalog.minimap)
                .disabled(editing == nil)
            Button(editing?.showsLibrary == true ? "Hide Library Panel" : ShortcutCatalog.libraryPanel.title) {
                editing?.toggleLibrary()
            }
            .shortcut(ShortcutCatalog.libraryPanel)
            .disabled(editing == nil)
            Divider()
            // Plain letter keys, handled by the Map so text fields keep them; listed in ⌘/.
            Menu("Tool") {
                ForEach(CanvasTool.allCases) { tool in
                    Toggle(isOn: Binding(
                        get: { editing?.tool == tool },
                        set: { if $0 { editing?.setTool(tool) } }
                    )) {
                        Text("\(tool.label)    \(String(tool.key).uppercased())")
                    }
                }
            }
            .disabled(editing?.viewMode != .map)
            Button(ShortcutCatalog.addNote.title) { editing?.addNote() }
                .disabled(editing == nil)
            Button("Add Text") { editing?.addText() }
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

        #if DEBUG
        CommandMenu("Debug") {
            Button("Generate 500-Node Board") { debug?.makeStressCanvas() }
                .disabled(debug == nil)
            Toggle("Show Frame Rate", isOn: $showsFrameRate)
        }
        #endif

        CommandGroup(replacing: .help) {
            Button(ShortcutCatalog.showShortcuts.title) { shortcuts?.show() }
                .shortcut(ShortcutCatalog.showShortcuts)
                .disabled(shortcuts == nil)
        }
    }
}
#endif

/// Something asked of the open Canvas from outside it, e.g. by the ⌘K palette.
/// `canvasID` says which Canvas it's for; each request is new, so the same one can be asked twice.
struct CanvasRequest: Equatable {
    enum Action: Equatable {
        case focus(UUID)
        case view(CanvasViewMode)
        case addNote, addSubIdea, find, toggleInspector, toggleLinkMode, toggleMinimap
    }

    let id = UUID()
    let canvasID: UUID
    let action: Action
}

/// File › Go To… (⌘K).
struct PaletteAction {
    var show: @MainActor () -> Void
}

/// Debug › Generate 500-Node Canvas.
struct DebugActions {
    var makeStressCanvas: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var showPalette: PaletteAction?
    @Entry var debugActions: DebugActions?
}
