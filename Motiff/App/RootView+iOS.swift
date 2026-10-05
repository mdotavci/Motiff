#if os(iOS)
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case inbox, library, canvases, boards, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @State private var tab: AppTab = Self.launchTab
    /// The Canvas open in the Canvases tab.
    @State private var canvasPath: [UUID] = []

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                InboxView()
            }
            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                LibraryView()
            }
            Tab("Canvases", systemImage: "point.3.connected.trianglepath.dotted", value: .canvases) {
                CanvasListView(path: $canvasPath)
            }
            Tab("Boards", systemImage: "rectangle.stack", value: .boards) {
                BoardsView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        // UI stays black/white/grey; red is reserved for focus and status.
        .tint(.primary)
        // Shake to undo reaches SwiftData through the window's undo manager.
        .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) {
            context.undoManager = undoManager
        }
        #if DEBUG
        .task { await applyLaunchRoute() }
        #endif
    }

    /// The tab `-MotiffOpen` names (Debug builds), set before the first frame.
    private static var launchTab: AppTab {
        #if DEBUG
        switch DebugLaunchRoute.open ?? "" {
        case "inbox": return .inbox
        case "boards": return .boards
        case "canvases": return .canvases
        case let route where route.hasPrefix("canvas:"): return .canvases
        default: return .library
        }
        #else
        return .library
        #endif
    }

    #if DEBUG
    /// Opens the Canvas named by `-MotiffOpen canvas:<title>`; CI then screenshots the simulator.
    private func applyLaunchRoute() async {
        guard let route = DebugLaunchRoute.open, route.hasPrefix("canvas:") else { return }
        let title = String(route.dropFirst("canvas:".count))
        // Seeding also runs at launch; wait for the seeded Canvas to be there.
        for _ in 0..<20 {
            let all = (try? context.fetch(FetchDescriptor<Canvas>())) ?? []
            if let canvas = all.first(where: { $0.title == title }) {
                tab = .canvases
                canvasPath = [canvas.id]
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
    #endif
}

#Preview {
    RootView()
}
#endif
