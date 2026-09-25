import SwiftUI

struct ShareView: View {
    let onSave: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save to Motiff")
                    .font(.headline)
                Text(AppGroup.isAvailable ? "Lands in Inbox." : "App Group not available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
        .tint(.primary)
    }
}
