import SwiftUI

/// What you can do to one node: right-click it on the Mac, long-press it on iPhone. Each item
/// selects the node first, then does what its key would. In the Outline it also moves the row.
struct NodeMenu: View {
    let node: CanvasNode
    let controller: CanvasController
    var inOutline = false

    var body: some View {
        if node.isLine {
            lineItems
        } else {
            nodeItems
        }
    }

    /// A free arrow or line: its color, its arrowheads, delete.
    @ViewBuilder
    private var lineItems: some View {
        colorMenu
        Toggle("Arrowhead at the End", isOn: Binding(
            get: { node.shape == .arrow },
            set: { on in controller.update { CanvasGraph.setArrowheads(of: node, start: node.hasStartArrow, end: on) } }
        ))
        Toggle("Arrowhead at the Start", isOn: Binding(
            get: { node.hasStartArrow },
            set: { on in controller.update { CanvasGraph.setArrowheads(of: node, start: on, end: node.shape == .arrow) } }
        ))
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            act { controller.deleteSelection(branch: false) }
        }
    }

    @ViewBuilder
    private var nodeItems: some View {
        Button("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
            controller.openDetail(node.id)
        }
        Button("Edit Text", systemImage: "pencil") {
            controller.select(node.id)
            controller.beginEditing(node.id)
        }
        Divider()
        Button("Add Note", systemImage: "note.text.badge.plus") {
            act { controller.addNote() }
        }
        Button("Add Sub-Idea", systemImage: "plus.circle") {
            act { controller.addSubIdea() }
        }
        Menu("Category", systemImage: "circle.lefthalf.filled") {
            ForEach(Array(controller.canvas.sortedCategories.enumerated()), id: \.element.id) { index, category in
                Button(category.name) {
                    act { controller.assignCategory(number: index + 1) }
                }
            }
            Divider()
            Button("None") {
                act { controller.assignCategory(number: 0) }
            }
        }
        colorMenu
        Button("Link To…", systemImage: "link") {
            controller.startLink(from: node.id)
        }
        if inOutline {
            Divider()
            Button("Put Under the Row Above", systemImage: "increase.indent") {
                act { controller.indentSelected() }
            }
            Button("Move Up a Level", systemImage: "decrease.indent") {
                act { controller.outdentSelected() }
            }
            Button("Move Up", systemImage: "arrow.up") {
                act { controller.moveSelected(by: -1) }
            }
            Button("Move Down", systemImage: "arrow.down") {
                act { controller.moveSelected(by: 1) }
            }
        }
        if node.reference?.copyablePrompt != nil {
            Divider()
            Button("Copy Prompt", systemImage: "doc.on.doc") {
                act { controller.copyPrompt() }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            act { controller.deleteSelection(branch: false) }
        }
    }

    private var colorMenu: some View {
        Menu("Color", systemImage: "paintpalette") {
            ForEach(CanvasCategory.swatches, id: \.hex) { swatch in
                Button(swatch.name) {
                    act { controller.setColor(swatch.hex) }
                }
            }
            Divider()
            Button(node.kind == .text ? "Automatic" : "Category Color") {
                act { controller.setColor(nil) }
            }
            Button("More Colors…") {
                act { controller.openColorPicker() }
            }
        }
    }

    private func act(_ action: () -> Void) {
        controller.select(node.id)
        action()
    }
}
