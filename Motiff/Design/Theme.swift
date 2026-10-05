import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Theme {
    /// The single accent. Focus and status only.
    static let accent = Color(red: 0.886, green: 0.137, blue: 0.102)

    /// 8pt grid.
    static let unit: CGFloat = 8
    static let gutter: CGFloat = 16
    /// Gap between grid tiles. Tiles have square corners, so the grid reads as one wall.
    static let gridGap: CGFloat = 2

    // MARK: Canvas

    /// Behind the Map.
    static let canvasGround = dynamic(light: 0xF4F4F2, dark: 0x141414)
    static let cardSurface = dynamic(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let cardBorder = dynamic(light: 0xDADAD6, dark: 0x38383A)
    /// Fill of an Idea with no category.
    static let neutralIdea = dynamic(light: 0xD1D1D6, dark: 0x3A3A3C)
    static let cardCorner: CGFloat = 10

    /// A color that follows light and dark mode, from two 0xRRGGBB values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return platformColor(isDark ? dark : light)
        })
        #else
        Color(uiColor: UIColor { traits in
            platformColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }

    #if os(macOS)
    private static func platformColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: channel(hex, 16), green: channel(hex, 8), blue: channel(hex, 0), alpha: 1)
    }
    #else
    private static func platformColor(_ hex: UInt32) -> UIColor {
        UIColor(red: channel(hex, 16), green: channel(hex, 8), blue: channel(hex, 0), alpha: 1)
    }
    #endif

    private static func channel(_ hex: UInt32, _ shift: UInt32) -> CGFloat {
        CGFloat((hex >> shift) & 0xFF) / 255
    }
}

extension View {
    /// Small uppercase label used for section headers and metadata keys.
    func motiffLabel() -> some View {
        font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Left-aligned empty state. No illustration.
struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(title).motiffLabel()
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.gutter)
    }
}
