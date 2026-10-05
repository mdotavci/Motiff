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

extension HexColor {
    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// "#RRGGBB".
    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// `amount` of the way to `other`.
    func mixed(with other: HexColor, amount: Double) -> HexColor {
        HexColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    /// WCAG contrast ratio, 1 to 21.
    func contrast(with other: HexColor) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This color, mixed toward `toward` a step at a time until it reads at `ratio` on `ground`.
    func readable(on ground: HexColor, ratio: Double, toward: HexColor) -> HexColor {
        var color = self
        var amount = 0.0
        while color.contrast(with: ground) < ratio, amount < 1 {
            amount += 0.05
            color = mixed(with: toward, amount: amount)
        }
        return color
    }

    static let white = HexColor(red: 1, green: 1, blue: 1)
    static let black = HexColor(red: 0, green: 0, blue: 0)
}

/// Turning a stored color into what's drawn.
enum Palette {
    /// Lines and words in this color: the swatch's ink on light grounds and its fill (or dark
    /// line) on dark ones. A custom color is darkened or lightened until it reads at 4.5:1.
    static func ink(_ hex: String) -> Color {
        guard let color = HexColor(hex) else { return .primary }
        let light: HexColor
        let dark: HexColor
        if let swatch = CanvasCategory.swatch(for: hex) {
            light = HexColor(swatch.ink) ?? color
            dark = HexColor(swatch.onDark) ?? color
        } else {
            light = color.readable(on: lightGround, ratio: 4.5, toward: .black)
            dark = color.readable(on: darkGround, ratio: 4.5, toward: .white)
        }
        return Theme.dynamic(light: light.packed, dark: dark.packed)
    }

    /// A fill, as drawn; nil stays nil.
    static func fill(_ hex: String?) -> Color? {
        hex.flatMap(HexColor.init)?.color
    }

    /// Words on a fill: the chosen text color's ink, or black or white for the fill.
    static func text(on fill: String?, chosen: String?) -> Color {
        if let chosen, let color = HexColor(chosen) {
            // On a fill, the chosen color as it reads there; on the ground, adaptive.
            guard let fill = fill.flatMap(HexColor.init) else { return ink(chosen) }
            let ground = fill.luminance > 0.4 ? HexColor.black : HexColor.white
            return color.readable(on: fill, ratio: 4.5, toward: ground).color
        }
        return fill.flatMap(HexColor.init)?.textColor ?? .primary
    }

    /// Fills light enough to vanish into a white card or the light ground get an outline.
    static func needsOutline(_ hex: String?) -> Bool {
        (hex.flatMap(HexColor.init)?.luminance ?? 1) > 0.8
    }

    private static let lightGround = HexColor("#F4F4F2") ?? .white
    private static let darkGround = HexColor("#141414") ?? .black
}

private extension HexColor {
    var packed: UInt32 {
        UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }
}
