import SwiftUI

struct InboxView: View {
    var body: some View {
        NavigationStack {
            EmptyState(title: "Inbox", message: "New saves appear here.")
                .navigationTitle("Inbox")
        }
    }
}
