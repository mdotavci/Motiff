import SwiftUI

/// The palette as a grid of dots, a reset, and Custom… for any other color. Used by the
/// selection bar, the inspector and the legend's category editor.
struct ColorPalettePicker: View {
    /// The stored color now; its dot is checked.
    let current: String?
    /// What "no color" means here: "Category Color", "Automatic", "Grey". Nil hides the reset.
    var resetTitle: String?
    let pick: (String?) -> Void

    /// The custom color being chosen; applied a moment after it stops changing, so dragging
    /// through the color wheel is one Undo step, not fifty.
    @State private var custom: Color = .gray
    @State private var applyTask: Task<Void, Never>?
    @Environment(\.self) private var environment

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 8)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CanvasCategory.swatches, id: \.hex) { swatch in
                    Button { pick(swatch.hex) } label: {
                        SwatchDot(hex: swatch.hex, isOn: swatch.hex.caseInsensitiveCompare(current ?? "") == .orderedSame)
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                }
            }
            HStack(spacing: 12) {
                if let resetTitle {
                    Button(resetTitle) { pick(nil) }
                        .buttonStyle(.borderless)
                        .disabled(current == nil)
                }
                Spacer(minLength: 0)
                ColorPicker("Custom…", selection: $custom, supportsOpacity: false)
                    .fixedSize()
            }
            .font(.callout)
            Text("Red is kept for showing what's selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if let color = current.flatMap(HexColor.init)?.color { custom = color }
        }
        .onChange(of: custom) { _, color in
            let resolved = color.resolve(in: environment)
            let hex = HexColor(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue)).hex
            guard hex.caseInsensitiveCompare(current ?? "") != .orderedSame else { return }
            applyTask?.cancel()
            applyTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                pick(hex)
            }
        }
    }
}

/// One palette color as a dot, outlined when it's light enough to vanish, checked when chosen.
struct SwatchDot: View {
    let hex: String
    var isOn = false
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(Palette.fill(hex) ?? .gray)
            .frame(width: size, height: size)
            .overlay {
                if Palette.needsOutline(hex) {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                }
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(HexColor(hex)?.textColor ?? .primary)
                }
            }
            .contentShape(Circle())
    }
}
