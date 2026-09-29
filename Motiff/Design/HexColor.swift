import SwiftUI

/// A "#RRGGBB" color, as categories store them, with what reads on top of it.
struct HexColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init?(_ hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Near-black or white, whichever has more contrast on this color.
    var textColor: Color {
        let onDark = (luminance + 0.05) / (Self.inkLuminance + 0.05)
        let onWhite = 1.05 / (luminance + 0.05)
        return onDark >= onWhite ? Self.ink : .white
    }

    /// #141414, the dark text used on light category colors.
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.078)
    private static let inkLuminance = 0.0069
}

extension CanvasCategory {
    var hexColor: HexColor? { HexColor(colorHex) }
    var color: Color { hexColor?.color ?? .gray }
}
