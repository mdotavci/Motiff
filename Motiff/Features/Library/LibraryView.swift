import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            EmptyState(title: "Library", message: "Everything you keep.")
                .navigationTitle("Library")
        }
    }
}
