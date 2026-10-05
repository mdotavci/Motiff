import SwiftUI

/// A small bar floating over what's selected on the Map. For nodes: their color, their words'
/// color, Text size, and the node menu. For a line: its color, its arrow, its label, delete.
/// C opens the colors from the keyboard; A turns a line's arrow on or off.
struct SelectionBar: View {
    @Bindable var controller: CanvasController
    /// Opens the Label… alert for a line.
    let labelEdge: (CanvasSnapshot.Edge) -> Void

    @State private var showsTextColors = false

    var body: some View {
        HStack(spacing: 2) {
            colorButton
            if let edge = controller.selectedEdge {
                edgeControls(edge)
            } else {
                nodeControls
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .fixedSize()
    }

    private var colorButton: some View {
        Button {
            controller.showsColorPicker = true
        } label: {
            Group {
                if let hex = controller.selectionColorHex {
                    SwatchDot(hex: hex, size: 18)
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .help("Color (\(ShortcutCatalog.color.keys))")
        .accessibilityLabel("Color")
        .popover(isPresented: $controller.showsColorPicker, arrowEdge: .bottom) {
            ColorPalettePicker(
                current: controller.selectionColorHex,
                resetTitle: resetTitle
            ) { hex in
                controller.setColor(hex)
            }
            .padding(12)
            .frame(width: 280)
        }
    }

    private var resetTitle: String {
        if controller.selectedEdge != nil { return "Grey" }
        if controller.selectedNodes.allSatisfy({ $0.kind == .text }) { return "Automatic" }
        return "Category Color"
    }

    @ViewBuilder
    private var nodeControls: some View {
        let nodes = controller.selectedNodes
        // Words in a color: Ideas and Notes. Text's own color is the dot already.
        if nodes.contains(where: { $0.kind == .idea || $0.kind == .note }) {
            Button {
                showsTextColors = true
            } label: {
                VStack(spacing: 1) {
                    Text("A").font(.system(size: 13, weight: .semibold))
                    Capsule()
                        .fill(nodes.first?.textColorHex.map(Palette.ink) ?? Color.primary)
                        .frame(width: 14, height: 3)
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .help("Text Color")
            .accessibilityLabel("Text Color")
            .popover(isPresented: $showsTextColors, arrowEdge: .bottom) {
                ColorPalettePicker(current: nodes.first?.textColorHex, resetTitle: "Automatic") { hex in
                    controller.setTextColor(hex)
                }
                .padding(12)
                .frame(width: 280)
            }
        }
        if nodes.contains(where: { $0.kind == .text }) {
            Menu {
                ForEach(TextSize.allCases) { size in
                    Button(size.label) { controller.setTextSizeOfSelection(size) }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 30, height: 30)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Text Size")
        }
        if nodes.count == 1, let node = nodes.first {
            Divider().frame(height: 18).padding(.horizontal, 2)
            Menu {
                NodeMenu(node: node, controller: controller)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More (\(ShortcutCatalog.nodeMenu.keys))")
        }
    }

    @ViewBuilder
    private func edgeControls(_ edge: CanvasSnapshot.Edge) -> some View {
        Button(edge.hasArrow ? "Hide Arrow" : "Show Arrow", systemImage: edge.hasArrow ? "arrow.right" : "line.diagonal") {
            controller.toggleArrow()
        }
        .frame(width: 30, height: 30)
        .help(edge.hasArrow ? "Hide the arrowhead (\(ShortcutCatalog.arrow.keys))" : "Show an arrowhead (\(ShortcutCatalog.arrow.keys))")
        Button("Label…", systemImage: "character.cursor.ibeam") { labelEdge(edge) }
            .frame(width: 30, height: 30)
            .help("Label the line")
        Divider().frame(height: 18).padding(.horizontal, 2)
        Button("Delete Line", systemImage: "trash") { controller.deleteEdge(edge) }
            .frame(width: 30, height: 30)
            .help("Delete the line (\(ShortcutCatalog.delete.keys))")
    }
}
