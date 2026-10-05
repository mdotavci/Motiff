#if os(iOS)
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case inbox, library, canvases, boards, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @State private var tab: AppTab = .library
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

    #if DEBUG
    /// Opens the tab (and Canvas) named by `-MotiffOpen`; CI then screenshots the simulator.
    private func applyLaunchRoute() async {
        guard let route = DebugLaunchRoute.open else { return }
        // Seeding also runs at launch; give it a moment so a seeded Canvas can be found.
        try? await Task.sleep(for: .seconds(1.5))
        switch route {
        case "inbox": tab = .inbox
        case "boards": tab = .boards
        case "canvases": tab = .canvases
        case let route where route.hasPrefix("canvas:"):
            let title = String(route.dropFirst("canvas:".count))
            let all = (try? context.fetch(FetchDescriptor<Canvas>())) ?? []
            tab = .canvases
            if let canvas = all.first(where: { $0.title == title }) { canvasPath = [canvas.id] }
        default: tab = .library
        }
    }
    #endif
}

#Preview {
    RootView()
}
#endif
