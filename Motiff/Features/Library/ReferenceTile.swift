import SwiftUI

/// One Reference in a grid. Media only, square corners, with small status marks:
/// origin letter top-leading, GIF/video mark top-trailing, red dot if the AI read failed.
struct ReferenceTile: View {
    let reference: Reference
    let width: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(1 / reference.displayAspectRatio, contentMode: .fit)
            .overlay {
                ThumbnailImage(url: reference.mediaURL, pointSize: width * max(reference.displayAspectRatio, 1))
            }
            .overlay(alignment: .topLeading) {
                OriginBadge(origin: reference.origin)
                    .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if reference.mediaType != .image {
                    MotionMark(type: reference.mediaType)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if reference.aiState == .failed {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [reference.origin.label, reference.mediaType.label]
        let why = reference.why.map(\.label)
        if !why.isEmpty { parts.append("kept for " + why.joined(separator: ", ")) }
        if let note = reference.whyNote, !note.isEmpty { parts.append(note) }
        if reference.aiState == .failed { parts.append("tagging failed") }
        return parts.joined(separator: ", ")
    }
}

/// The origin letter in an 18pt square.
struct OriginBadge: View {
    let origin: Origin

    var body: some View {
        Text(origin.letter)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(.black.opacity(0.55))
            .accessibilityLabel(origin.label)
    }
}

private struct MotionMark: View {
    let type: MediaType

    var body: some View {
        Group {
            if type == .gif {
                Text("GIF").font(.caption2.weight(.bold))
            } else {
                Image(systemName: "play.fill").font(.caption2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .frame(minWidth: 18, minHeight: 18)
        .background(.black.opacity(0.55))
    }
}

extension MediaType {
    var label: String {
        switch self {
        case .image: "Image"
        case .gif: "GIF"
        case .video: "Video"
        }
    }
}
