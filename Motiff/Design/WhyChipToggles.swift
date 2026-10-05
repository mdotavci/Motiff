import SwiftUI

/// The eight Why chips; tap to turn one on or off. Black and white only.
struct WhyChipToggles: View {
    let selected: [WhyChip]
    let toggle: (WhyChip) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(WhyChip.allCases, id: \.self) { chip in
                let isOn = selected.contains(chip)
                Button {
                    toggle(chip)
                } label: {
                    Text(chip.label)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(isOn ? Theme.canvasGround : Color.primary)
                        .background(isOn ? Color.primary : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
