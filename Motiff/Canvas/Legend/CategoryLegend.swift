import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The bar at the top of the Map: categories with their counts and keys, then prompt purposes.
/// Click one to show only that (everything else dims), click again to show all; ⇧-click to
/// pick several. The pencil edits the categories. When the bar doesn't fit, it drops the names.
struct CategoryLegend: View {
    let controller: CanvasController

    @State private var isEditing = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(showsNames: true)
            bar(showsNames: false)
        }
    }

    private func bar(showsNames: Bool) -> some View {
        let categories = controller.canvas.sortedCategories
        return HStack(spacing: 2) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                let isOn = controller.categoryFilter.contains(category.id)
                LegendChip(isOn: isOn, isMuted: !controller.categoryFilter.isEmpty && !isOn) {
                    controller.toggleCategoryFilter(category.id, extending: Self.shiftIsDown)
                } label: {
                    Circle().fill(category.color).frame(width: 9, height: 9)
                    if showsNames { Text(category.name) }
                    Text(verbatim: "\(category.nodes.count)").foregroundStyle(.secondary)
                }
                .help(index < 9 ? "\(category.name): show only this (⇧-click for more). Press \(index + 1) to give it to the selection."
                                : "\(category.name): show only this (⇧-click for more)")
            }

            Divider().frame(height: 16).padding(.horizontal, 4)

            ForEach(PromptPurpose.allCases, id: \.self) { purpose in
                let isOn = controller.purposeFilter.contains(purpose)
                LegendChip(isOn: isOn, isMuted: !controller.purposeFilter.isEmpty && !isOn) {
                    controller.togglePurposeFilter(purpose, extending: Self.shiftIsDown)
                } label: {
                    Image(systemName: purpose.systemImage)
                    if showsNames { Text(purpose.label) }
                }
                .help("\(purpose.label) prompts only (⇧-click for more)")
            }

            if controller.isFiltering {
                Button("Clear") { controller.clearFilters() }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 6)
                    .help("Show everything (\(ShortcutCatalog.clearFilter.keys))")
            }

            Button("Edit Categories", systemImage: "pencil") { isEditing = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .help("Rename, recolor, reorder, add or delete categories")
                .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                    CategoryEditor(controller: controller)
                }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .fixedSize()
    }

    static var shiftIsDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }
}

/// One filter in the legend. On: a light fill and full-strength text. Muted (another one is
/// on): faded. Black and white only; the category's own dot carries its color.
private struct LegendChip<Label: View>: View {
    let isOn: Bool
    let isMuted: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { label }
                .fontWeight(isOn ? .semibold : .regular)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(isOn ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .opacity(isMuted ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Editing

/// Rename, recolor, reorder, add and delete the Canvas's categories. Each change is one Undo step.
private struct CategoryEditor: View {
    let controller: CanvasController

    var body: some View {
        let categories = controller.canvas.sortedCategories
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text("Categories").motiffLabel()
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: 6) {
                    SwatchButton(category: category, controller: controller)
                    CommitField(prompt: "Name", value: category.name) { name in
                        controller.update { CanvasGraph.renameCategory(category, to: name) }
                    }
                    Text(verbatim: index < 9 ? "\(index + 1)" : "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                        .help(index < 9 ? "Press \(index + 1) to give this category to the selection" : "")
                    Button("Move Up", systemImage: "chevron.up") {
                        controller.update { CanvasGraph.moveCategory(category, by: -1) }
                    }
                    .disabled(index == 0)
                    Button("Move Down", systemImage: "chevron.down") {
                        controller.update { CanvasGraph.moveCategory(category, by: 1) }
                    }
                    .disabled(index == categories.count - 1)
                    Button("Delete", systemImage: "xmark") { controller.deleteCategory(category) }
                        .help("Delete the category. Its cards and Ideas stay, uncolored.")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Button("Add Category", systemImage: "plus") { _ = controller.addCategory() }
                .buttonStyle(.borderless)
                .padding(.top, 4)
        }
        .padding(Theme.gutter)
        .frame(width: 340)
    }
}

/// The category's color; click for the ten swatches. There's no free picker, so no red.
private struct SwatchButton: View {
    let category: CanvasCategory
    let controller: CanvasController

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Circle()
                .fill(category.color)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Color")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5), spacing: 8) {
                ForEach(CanvasCategory.swatches, id: \.hex) { swatch in
                    Button {
                        controller.update { CanvasGraph.setColor(category, to: swatch.hex) }
                        isPicking = false
                    } label: {
                        Circle()
                            .fill(HexColor(swatch.hex)?.color ?? .gray)
                            .frame(width: 22, height: 22)
                            .overlay {
                                if swatch.hex == category.colorHex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(HexColor(swatch.hex)?.textColor ?? .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                }
            }
            .padding(12)
        }
    }
}
