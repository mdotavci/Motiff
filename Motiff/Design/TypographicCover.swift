import SwiftUI

/// Stands in for media on a prompt that has none: the prompt's first words, set large.
/// On a Canvas it takes the card's category color; in the Library it's neutral.
struct TypographicCover: View {
    let text: String
    var background: HexColor?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Text(Self.leadingWords(of: text))
                .font(.system(size: max(12, width * 0.1), weight: .bold))
                .lineSpacing(0)
                .foregroundStyle(background?.textColor ?? Color.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .padding(max(8, width * 0.07))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(background?.color ?? Color.primary.opacity(0.08))
        .accessibilityLabel(text)
    }

    /// The prompt's first sentence, cut to about six words.
    static func leadingWords(of text: String, limit: Int = 6) -> String {
        let firstSentence = text
            .split(whereSeparator: { ".:\n".contains($0) })
            .first
            .map(String.init) ?? text
        let words = firstSentence.split(whereSeparator: \.isWhitespace)
        let kept = words.prefix(limit).joined(separator: " ")
        return words.count > limit ? kept + "…" : kept
    }
}
