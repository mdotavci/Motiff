import SwiftUI

/// How big Library tiles are. ⌘+ makes them bigger (fewer columns), ⌘− smaller.
/// Stored as a level in user defaults so the menu commands and the grid share it.
enum LibraryDensity {
    static let storageKey = "library.density"

    /// Target tile width in points for each level, smallest first.
    static let tileWidths: [CGFloat] = [110, 150, 200, 280, 400]
    static let defaultLevel = 2

    static func tileWidth(level: Int) -> CGFloat {
        tileWidths[clamped(level)]
    }

    static func clamped(_ level: Int) -> Int {
        min(max(level, 0), tileWidths.count - 1)
    }

    static func canGrow(_ level: Int) -> Bool { level < tileWidths.count - 1 }
    static func canShrink(_ level: Int) -> Bool { level > 0 }
}

#if os(macOS)
/// View menu: Larger / Smaller / Default Thumbnails. With a Canvas open, the same three
/// shortcuts zoom the Map instead.
struct LibraryCommands: Commands {
    @AppStorage(LibraryDensity.storageKey) private var level = LibraryDensity.defaultLevel
    @FocusedValue(\.canvasZoom) private var canvasZoom

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            if let canvasZoom {
                Button(ShortcutCatalog.zoomIn.title) { canvasZoom.zoomIn() }
                    .shortcut(ShortcutCatalog.zoomIn)
                Button(ShortcutCatalog.zoomOut.title) { canvasZoom.zoomOut() }
                    .shortcut(ShortcutCatalog.zoomOut)
                Button(ShortcutCatalog.fit.title) { canvasZoom.fit() }
                    .shortcut(ShortcutCatalog.fit)
            } else {
                Button(ShortcutCatalog.largerThumbnails.title) { level = LibraryDensity.clamped(level + 1) }
                    .shortcut(ShortcutCatalog.largerThumbnails)
                    .disabled(!LibraryDensity.canGrow(level))
                Button(ShortcutCatalog.smallerThumbnails.title) { level = LibraryDensity.clamped(level - 1) }
                    .shortcut(ShortcutCatalog.smallerThumbnails)
                    .disabled(!LibraryDensity.canShrink(level))
                Button(ShortcutCatalog.defaultThumbnails.title) { level = LibraryDensity.defaultLevel }
                    .shortcut(ShortcutCatalog.defaultThumbnails)
            }
            Divider()
        }
    }
}
#endif
