import SwiftUI

/// The Canvas as an indented list. ↑ ↓ move, ← → fold and unfold, Tab and ⇧Tab change what a
/// row belongs to, ⌥⌘↑ ⌥⌘↓ reorder. Return edits a row in place, Space opens it full size.
/// The keys are handled by the Canvas view around it, like the Map's.
struct CanvasOutlineView: View {
    let controller: CanvasController
    /// Gives the keyboard back to the Canvas view after a click.
    let focusCanvas: () -> Void

    var body: some View {
        let rows = controller.outlineRows
        let matches = controller.filterMatches
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        if let node = controller.node(row.id) {
                            OutlineRow(
                                row: row,
                                node: node,
                                controller: controller,
                                isDimmed: matches.map { !$0.contains(row.id) } ?? false,
                                focusCanvas: focusCanvas
                            )
                            .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, Theme.unit)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.selection) { _, selection in
                guard selection.count == 1, let id = selection.first else { return }
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
            }
        }
        .background(.background)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.clearSelection()
            focusCanvas()
        }
    }
}

private struct OutlineRow: View {
    let row: CanvasOutline.Row
    let node: CanvasNode
    let controller: CanvasController
    let isDimmed: Bool
    let focusCanvas: () -> Void

    var body: some View {
        let isSelected = controller.selection.contains(node.id)
        let isEditing = controller.editingID == node.id
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 20, height: 1)

            Group {
                if row.hasChildren {
                    Button {
                        controller.toggleCollapsed(node.id)
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(controller.collapsed.contains(node.id) ? 0 : 90))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(controller.collapsed.contains(node.id) ? "Unfold (→)" : "Fold (←)")
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }

            OutlineIcon(node: node)

            if isEditing {
                InlineEditor(
                    controller: controller,
                    nodeID: node.id,
                    prompt: node.isIdea ? "Name this idea" : "Text",
                    axis: node.kind == .note ? .vertical : .horizontal
                )
                .font(.system(size: 13, weight: node.isIdea ? .semibold : .regular))
            } else {
                Text(node.displayTitle)
                    .font(.system(size: 13, weight: node.isIdea ? .semibold : .regular))
                    .lineLimit(1)
            }

            if let label = node.parentLabel, !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.unit)

            if let purpose = node.reference?.purpose {
                Image(systemName: purpose.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(purpose.label)
            }
            if row.hasChildren, controller.collapsed.contains(node.id) {
                Text(verbatim: "\(node.children.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 30)
        .background(isSelected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            // Focus red marks the selected row, as the ring does on the Map.
            if isSelected {
                RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 2).padding(.vertical, 5)
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        .contentShape(Rectangle())
        // Right-click on the Mac, long-press on iPhone: the node's actions plus moving the row.
        .contextMenu {
            if !isEditing { NodeMenu(node: node, controller: controller, inOutline: true) }
        }
        .gesture(TapGesture().onEnded {
            controller.tap(node.id, extending: CategoryLegend.shiftIsDown)
            if controller.editingID == nil { focusCanvas() }
        }, including: isEditing ? .subviews : .all)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { controller.beginEditing(node.id) },
            including: isEditing ? .subviews : .all
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small mark for the row's kind: the Idea's colored dot, a card's thumbnail, a note or link glyph.
private struct OutlineIcon: View {
    let node: CanvasNode

    var body: some View {
        Group {
            switch node.kind {
            case .idea:
                Circle()
                    .fill(node.category?.color ?? Theme.neutralIdea)
                    .frame(width: 12, height: 12)
            case .reference, .prompt:
                if let reference = node.reference {
                    Group {
                        if reference.hasMedia {
                            ThumbnailImage(url: reference.mediaURL, pointSize: 22)
                        } else {
                            TypographicCover(text: reference.copyablePrompt ?? "", background: node.category?.hexColor)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(node.category?.color ?? .clear).frame(height: 2)
                    }
                }
            case .note:
                Image(systemName: "text.alignleft")
                    .foregroundStyle(node.category?.color ?? Color.secondary)
            case .link:
                Image(systemName: "link")
                    .foregroundStyle(node.category?.color ?? Color.secondary)
            case .text:
                Image(systemName: "textformat")
                    .foregroundStyle(node.category?.color ?? Color.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(width: 22, height: 22)
    }
}
