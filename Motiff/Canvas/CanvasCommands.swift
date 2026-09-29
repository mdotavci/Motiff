import SwiftUI

/// Canvas actions the menu bar can reach in the focused window.
struct CanvasActions {
    var newCanvas: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var canvasActions: CanvasActions?
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
