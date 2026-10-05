import SwiftUI

/// A small bar floating over what's selected on the board. For nodes: their color, their words'
/// color and size, a shape's border, an arrow's thickness, dashes and heads, and the node menu.
/// For a line: its color, thickness, dashes and heads, its label, delete.
/// C opens the colors from the keyboard; ⇧A turns a line's arrow on or off.
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
        if let fontSize = controller.selectionFontSize {
            FontSizeControl(controller: controller, size: fontSize)
        }
        let lines = nodes.filter(\.isLine)
        if !lines.isEmpty {
            StrokeMenu(controller: controller, choices: Self.lineWidths, systemImage: "line.diagonal")
            DashButton(controller: controller)
            HeadsMenu(controller: controller, start: lines[0].hasStartArrow, end: lines[0].shape == .arrow)
        } else if nodes.contains(where: { $0.kind == .shape }) {
            StrokeMenu(controller: controller, choices: Self.borderWidths, systemImage: "square.dashed")
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

    static let lineWidths = [
        StrokeChoice(name: "Thin", width: 1.5), StrokeChoice(name: "Medium", width: 2.5),
        StrokeChoice(name: "Thick", width: 4), StrokeChoice(name: "Heavy", width: 6),
    ]
    static let borderWidths = [
        StrokeChoice(name: "No Border", width: 0), StrokeChoice(name: "Thin", width: 1.5), StrokeChoice(name: "Thick", width: 4),
    ]

    @ViewBuilder
    private func edgeControls(_ edge: CanvasSnapshot.Edge) -> some View {
        if edge.type == .relatesTo {
            StrokeMenu(controller: controller, choices: Self.lineWidths, systemImage: "line.diagonal")
            DashButton(controller: controller)
            HeadsMenu(controller: controller, start: edge.hasStartArrow, end: edge.hasArrow)
        } else {
            Button(edge.hasArrow ? "Hide Arrow" : "Show Arrow", systemImage: edge.hasArrow ? "arrow.right" : "line.diagonal") {
                controller.toggleArrow()
            }
            .frame(width: 30, height: 30)
            .help(edge.hasArrow ? "Hide the arrowhead (\(ShortcutCatalog.arrow.keys))" : "Show an arrowhead (\(ShortcutCatalog.arrow.keys))")
        }
        Button("Label…", systemImage: "character.cursor.ibeam") { labelEdge(edge) }
            .frame(width: 30, height: 30)
            .help("Label the line")
        Divider().frame(height: 18).padding(.horizontal, 2)
        Button("Delete Line", systemImage: "trash") { controller.deleteEdge(edge) }
            .frame(width: 30, height: 30)
            .help("Delete the line (\(ShortcutCatalog.delete.keys))")
    }
}

/// − 16 +: the letters' size, a step at a time, or any size from the menu.
private struct FontSizeControl: View {
    let controller: CanvasController
    let size: Double

    var body: some View {
        HStack(spacing: 0) {
            Button("Smaller Text", systemImage: "minus") { controller.stepFontSize(by: -1) }
                .frame(width: 22, height: 30)
                .help("Smaller text (\(ShortcutCatalog.smallerText.keys))")
            Menu {
                ForEach(CanvasController.fontSizes, id: \.self) { choice in
                    Button("\(Int(choice))") { controller.setFontSize(choice) }
                }
            } label: {
                Text("\(Int(size.rounded()))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(minWidth: 24, minHeight: 30)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Text size")
            Button("Bigger Text", systemImage: "plus") { controller.stepFontSize(by: 1) }
                .frame(width: 22, height: 30)
                .help("Bigger text (\(ShortcutCatalog.biggerText.keys))")
        }
    }
}

struct StrokeChoice: Hashable {
    let name: String
    let width: Double
}

/// How thick an arrow or line is, or a shape's border.
private struct StrokeMenu: View {
    let controller: CanvasController
    let choices: [StrokeChoice]
    let systemImage: String

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button {
                    controller.setStrokeWidth(choice.width)
                } label: {
                    if controller.selectionStrokeWidth == choice.width {
                        Label(choice.name, systemImage: "checkmark")
                    } else {
                        Text(choice.name)
                    }
                }
            }
        } label: {
            Image(systemName: systemImage)
                .fontWeight(.semibold)
                .frame(width: 30, height: 30)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Thickness")
        .accessibilityLabel("Thickness")
    }
}

/// Solid or dashed.
private struct DashButton: View {
    let controller: CanvasController

    var body: some View {
        let dashed = controller.selectionIsDashed
        Button {
            controller.toggleDashed()
        } label: {
            LineShape(start: CGPoint(x: 2, y: 9), end: CGPoint(x: 16, y: 9))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 3] : []))
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .help(dashed ? "Make it solid" : "Make it dashed")
        .accessibilityLabel(dashed ? "Dashed" : "Solid")
    }
}

/// Arrowheads at either end.
private struct HeadsMenu: View {
    let controller: CanvasController
    let start: Bool
    let end: Bool

    var body: some View {
        Menu {
            Toggle("At the End", isOn: Binding(get: { end }, set: { controller.setArrowheads(start: start, end: $0) }))
            Toggle("At the Start", isOn: Binding(get: { start }, set: { controller.setArrowheads(start: $0, end: end) }))
        } label: {
            Image(systemName: start && end ? "arrow.left.and.right" : end ? "arrow.right" : start ? "arrow.left" : "minus")
                .frame(width: 30, height: 30)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Arrowheads (\(ShortcutCatalog.arrow.keys) at the end)")
        .accessibilityLabel("Arrowheads")
    }
}
