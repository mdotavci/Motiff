import SwiftUI

/// What's on a Canvas, as an indented list. Stands in until the Map view (Canvas step 2).
struct CanvasSummaryView: View {
    let canvas: Canvas

    var body: some View {
        List {
            Section {
                ForEach(canvas.roots) { root in
                    NodeRows(node: root, depth: 0)
                }
                ForEach(canvas.unattachedNodes) { node in
                    NodeRows(node: node, depth: 0)
                }
            } header: {
                Text(summary)
            }

            if !canvas.categories.isEmpty {
                Section("Categories") {
                    ForEach(canvas.sortedCategories) { category in
                        Label {
                            Text(category.name)
                        } icon: {
                            Circle().fill(category.color).frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
        .navigationTitle(canvas.displayTitle)
    }

    private var summary: String {
        let nodes = canvas.nodes.count
        let links = canvas.links.count
        return "\(nodes) \(nodes == 1 ? "node" : "nodes") · \(links) \(links == 1 ? "link" : "links")"
    }
}

/// A node, then everything that belongs to it, indented.
private struct NodeRows: View {
    let node: CanvasNode
    let depth: Int

    var body: some View {
        row
        ForEach(node.sortedChildren) { child in
            NodeRows(node: child, depth: depth + 1)
        }
    }

    private var row: some View {
        HStack(spacing: Theme.unit) {
            marker
            Text(node.displayTitle)
                .fontWeight(node.isIdea ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            ForEach(relatedTitles, id: \.self) { title in
                Text("↔ \(title)")
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, CGFloat(depth) * Theme.unit * 3)
    }

    @ViewBuilder
    private var marker: some View {
        let color = node.category?.color ?? .secondary
        if node.isIdea {
            Circle().fill(color).frame(width: 10, height: 10)
        } else {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
        }
    }

    private var relatedTitles: [String] {
        node.outgoing.compactMap { $0.to?.displayTitle }
    }

    private var detail: String {
        switch node.kind {
        case .reference, .prompt:
            let purpose = node.reference?.purpose.map { " · \($0.label)" } ?? ""
            return node.kind.label + purpose
        default:
            return node.kind.label
        }
    }
}
