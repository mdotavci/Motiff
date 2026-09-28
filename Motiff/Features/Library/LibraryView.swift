import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Reference.createdAt, order: .reverse) private var references: [Reference]

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.unit)]

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Library")
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if references.isEmpty {
            EmptyState(title: "Library", message: "Everything you keep.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.unit) {
                    ForEach(references) { reference in
                        ReferenceThumbnail(reference: reference)
                    }
                }
                .padding(Theme.gutter)
            }
            #if os(macOS)
            .navigationTitle("Library — \(references.count)")
            #endif
        }
    }
}

private struct ReferenceThumbnail: View {
    let reference: Reference

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlatformImage(url: reference.mediaURL)
                .aspectRatio(CGFloat(reference.width) / CGFloat(max(reference.height, 1)), contentMode: .fill)
                .clipped()

            Text(reference.origin.letter)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
        }
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
