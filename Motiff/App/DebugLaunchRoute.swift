#if DEBUG
import Foundation
#if os(macOS)
import AppKit
#endif

/// Launch arguments that let CI (and agents) open a screen and snapshot it without clicking.
/// They land in UserDefaults' argument domain, so there's nothing to parse:
///
///     -MotiffOpen library | inbox | boards | canvas:<title>
///     -MotiffSnapshot <name>     writes Snapshots/<name>.png in the library folder (Mac)
///
/// See `.claude/skills/run-motiff/SKILL.md`.
enum DebugLaunchRoute {
    static var open: String? {
        UserDefaults.standard.string(forKey: "MotiffOpen")
    }

    static var snapshotName: String? {
        UserDefaults.standard.string(forKey: "MotiffSnapshot")
    }

    /// Time for the opened screen to load its thumbnails before the snapshot.
    static let settleSeconds: Double = 2

    static var snapshotsURL: URL {
        AppGroup.containerURL.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    #if os(macOS)
    static func selection(for route: String, canvases: [Canvas]) -> SidebarSelection {
        switch route {
        case "inbox": return .inbox
        case "boards": return .boards
        case let route where route.hasPrefix("canvas:"):
            let title = String(route.dropFirst("canvas:".count))
            if let canvas = canvases.first(where: { $0.title == title }) {
                return .canvas(canvas.id)
            }
            return .library
        default: return .library
        }
    }

    /// Draws the frontmost window, title bar and toolbar included, into a PNG.
    /// Uses the view hierarchy, so it needs no screen-recording permission.
    @MainActor
    static func writeSnapshot(named name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView
        else { return }
        let view = content.superview ?? content
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        try? data.write(to: snapshotsURL.appending(path: "\(name).png"))
    }
    #endif
}
#endif
