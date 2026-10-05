import SwiftUI

/// What a prompt is for, as a small square-cornered chip that matches `OriginBadge`.
struct PurposeBadge: View {
    let purpose: PromptPurpose

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: purpose.systemImage)
            Text(purpose.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .frame(minHeight: 18)
        .background(.black.opacity(0.55))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(purpose.label) prompt")
    }
}
