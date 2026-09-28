import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws small abstract placeholder images with plain CoreGraphics + ImageIO, so the seed
/// library isn't empty. No image assets are shipped; these are generated once, the first
/// time the app runs, and work identically on iOS and macOS.
enum PlaceholderImageGenerator {
    enum Style {
        case halves, circle, bands, corner
    }

    struct Spec {
        var background: CGColor
        var accent: CGColor
        var style: Style
    }

    static func pngData(size: CGSize, spec: Spec) -> Data? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let rect = CGRect(origin: .zero, size: size)
        context.setFillColor(spec.background)
        context.fill(rect)

        context.setFillColor(spec.accent)
        switch spec.style {
        case .halves:
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
        case .circle:
            let d = min(size.width, size.height) * 0.55
            context.fillEllipse(in: CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d))
        case .bands:
            let bandHeight = size.height / 7
            for i in stride(from: 0, to: 7, by: 2) {
                context.fill(CGRect(x: 0, y: CGFloat(i) * bandHeight, width: size.width, height: bandHeight))
            }
        case .corner:
            context.fill(CGRect(x: size.width * 0.4, y: 0, width: size.width * 0.6, height: size.height * 0.6))
        }

        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
