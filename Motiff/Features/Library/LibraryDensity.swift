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
                Button("Zoom In") { canvasZoom.zoomIn() }
                    .keyboardShortcut("+")
                Button("Zoom Out") { canvasZoom.zoomOut() }
                    .keyboardShortcut("-")
                Button("Fit to Screen") { canvasZoom.fit() }
                    .keyboardShortcut("0")
            } else {
                Button("Larger Thumbnails") { level = LibraryDensity.clamped(level + 1) }
                    .keyboardShortcut("+")
                    .disabled(!LibraryDensity.canGrow(level))
                Button("Smaller Thumbnails") { level = LibraryDensity.clamped(level - 1) }
                    .keyboardShortcut("-")
                    .disabled(!LibraryDensity.canShrink(level))
                Button("Default Thumbnail Size") { level = LibraryDensity.defaultLevel }
                    .keyboardShortcut("0")
            }
            Divider()
        }
    }
}
#endif
