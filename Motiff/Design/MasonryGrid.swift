import SwiftUI

/// A lazy masonry grid: items flow into the shortest column, each keeping its own aspect ratio.
///
/// Column placement is computed from aspect ratios alone, so it doesn't change as the window
/// resizes unless the column count does. Each column is its own `LazyVStack`, so off-screen
/// tiles are never built.
struct MasonryGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    /// Height divided by width for one item.
    let aspectRatio: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(distribute().enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { item in
                        content(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    /// Greedy shortest-column placement, in reading order. Heights are in units of column width.
    private func distribute() -> [[Item]] {
        let count = max(columns, 1)
        var result = Array(repeating: [Item](), count: count)
        var heights = Array(repeating: CGFloat.zero, count: count)
        for item in items {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            result[shortest].append(item)
            heights[shortest] += aspectRatio(item)
        }
        return result
    }

    /// How many columns of roughly `targetWidth` fit in `width`.
    static func columnCount(for width: CGFloat, targetWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (targetWidth + spacing)).rounded()))
    }
}
