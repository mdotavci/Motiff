import SwiftUI

/// What a node belongs to, what belongs to it, and what it's linked with. Click a row to go
/// to that node. With `detach` / `unlink` set, rows get a × (the inspector); without, they
/// only open (the detail view).
struct ConnectionList: View {
    let node: CanvasNode
    /// Also list what belongs to the node. The Idea detail shows those as a grid instead.
    var showsChildren = false
    let open: (CanvasNode) -> Void
    var detach: ((CanvasNode) -> Void)?
    var unlink: ((CanvasLink) -> Void)?

    var body: some View {
        if let parent = node.parent {
            DetailSection("Belongs to") {
                ConnectionRow(
                    node: parent, label: node.parentLabel, removeTitle: "Detach",
                    open: { open(parent) }, remove: removal(detach, node)
                )
            }
        }
        let children = node.sortedChildren
        if showsChildren, !children.isEmpty {
            DetailSection("Contains") {
                ForEach(children) { child in
                    ConnectionRow(
                        node: child, label: child.parentLabel, removeTitle: "Detach",
                        open: { open(child) }, remove: removal(detach, child)
                    )
                }
            }
        }
        let outgoing = node.outgoing.filter { $0.to != nil }
        if !outgoing.isEmpty {
            DetailSection("Linked to") {
                ForEach(outgoing) { link in
                    if let other = link.to {
                        ConnectionRow(
                            node: other, label: link.label, removeTitle: "Unlink",
                            open: { open(other) }, remove: removal(unlink, link)
                        )
                    }
                }
            }
        }
        let incoming = node.incoming.filter { $0.from != nil }
        if !incoming.isEmpty {
            DetailSection("Linked from") {
                ForEach(incoming) { link in
                    if let other = link.from {
                        ConnectionRow(
                            node: other, label: link.label, removeTitle: "Unlink",
                            open: { open(other) }, remove: removal(unlink, link)
                        )
                    }
                }
            }
        }
    }
}

/// `action` bound to `item`, or nil when there's no action (no × button).
private func removal<Item>(_ action: ((Item) -> Void)?, _ item: Item) -> (() -> Void)? {
    guard let action else { return nil }
    return { action(item) }
}

private struct ConnectionRow: View {
    let node: CanvasNode
    let label: String?
    let removeTitle: String
    let open: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.unit) {
            Button(action: open) {
                HStack(spacing: Theme.unit) {
                    Circle()
                        .fill(node.category?.color ?? Color.primary.opacity(0.25))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.displayTitle)
                            .lineLimit(1)
                        if let label, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go to \(node.kind.label)")
            if let remove {
                Button(removeTitle, systemImage: "xmark", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(removeTitle)
            }
        }
        .padding(.vertical, 3)
    }
}
