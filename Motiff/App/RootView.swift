import SwiftUI

enum AppTab: Hashable {
    case inbox, library, boards, settings
}

struct RootView: View {
    @State private var tab: AppTab = .library

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                InboxView()
            }
            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                LibraryView()
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
    }
}

#Preview {
    RootView()
}
