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

extension FocusedValues {
    @Entry var canvasActions: CanvasActions?
    @Entry var canvasZoom: CanvasZoomActions?
}

#if os(macOS)
/// File › New Canvas (⌘N). Replaces New Window: Motiff is a single-window app.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Canvas") { actions?.newCanvas() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
    }
}
#endif
