#if os(macOS)
import SwiftUI

enum SidebarItem: Hashable, CaseIterable {
    case inbox, library, boards

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .library: "Library"
        case .boards: "Boards"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .library: "square.grid.2x2"
        case .boards: "rectangle.stack"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarItem? = .library

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .inbox: InboxView()
            case .boards: BoardsView()
            case .library, nil: LibraryView()
            }
        }
        .tint(.primary)
    }
}

#Preview {
    RootView()
}
#endif
