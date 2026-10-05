#if os(iOS)
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case inbox, library, boards, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @State private var tab: AppTab = Self.launchTab
    /// The board open in the Boards tab.
    @State private var boardPath: [UUID] = []

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                InboxView()
            }
            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                LibraryView()
            }
            Tab("Boards", systemImage: "rectangle.3.group", value: .boards) {
                CanvasListView(path: $boardPath)
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
        case "boards", "canvases": return .boards
        case let route where DebugLaunchRoute.boardTitle(in: route) != nil: return .boards
        default: return .library
        }
        #else
        return .library
        #endif
    }

    #if DEBUG
    /// Opens the board named by `-MotiffOpen board:<title>`; CI then screenshots the simulator.
    private func applyLaunchRoute() async {
        guard let route = DebugLaunchRoute.open, let title = DebugLaunchRoute.boardTitle(in: route) else { return }
        // Seeding also runs at launch; wait for the seeded board to be there.
        for _ in 0..<20 {
            let all = (try? context.fetch(FetchDescriptor<Canvas>())) ?? []
            if let canvas = all.first(where: { $0.title == title }) {
                tab = .boards
                boardPath = [canvas.id]
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
