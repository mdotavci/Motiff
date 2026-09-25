import SwiftUI

enum Theme {
    /// The single accent. Focus and status only.
    static let accent = Color(red: 0.886, green: 0.137, blue: 0.102)

    /// 8pt grid.
    static let unit: CGFloat = 8
    static let gutter: CGFloat = 16
}

extension View {
    /// Small uppercase label used for section headers and metadata keys.
    func motiffLabel() -> some View {
        font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Left-aligned empty state. No illustration.
struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(title).motiffLabel()
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.gutter)
    }
}
