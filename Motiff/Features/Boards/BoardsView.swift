import SwiftUI

struct BoardsView: View {
    var body: some View {
        NavigationStack {
            EmptyState(title: "Boards", message: "No boards yet.")
                .navigationTitle("Boards")
        }
    }
}
