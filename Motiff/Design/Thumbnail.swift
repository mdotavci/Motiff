import ImageIO
import SwiftUI

/// A downsampled image decoded off the main thread. CGImage is immutable, so sharing it is safe.
final class DecodedThumbnail: @unchecked Sendable {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Decodes media files into small thumbnails with ImageIO and keeps them in memory.
///
/// Sizes are rounded up to 256px steps, so changing grid density reuses cached images
/// instead of decoding again. GIFs give their first frame. Videos give nothing yet.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, DecodedThumbnail>()

    init() {
        cache.countLimit = 400
    }

    static func bucket(for pixels: CGFloat) -> Int {
        max(256, Int((pixels / 256).rounded(.up)) * 256)
    }

    func cached(_ url: URL, maxPixelSize: Int) -> DecodedThumbnail? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    func load(_ url: URL, maxPixelSize: Int) async -> DecodedThumbnail? {
        if let hit = cached(url, maxPixelSize: maxPixelSize) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) {
            ThumbnailCache.decode(url, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: Self.key(url, maxPixelSize))
        }
        return decoded
    }

    private static func key(_ url: URL, _ size: Int) -> NSString {
        "\(url.path)#\(size)" as NSString
    }

    private static func decode(_ url: URL, maxPixelSize: Int) -> DecodedThumbnail? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return DecodedThumbnail(cgImage: image)
    }
}

/// Fills its frame with a thumbnail of the file at `url`, loaded in the background.
/// Shows a flat grey until the image is ready.
struct ThumbnailImage: View {
    let url: URL
    /// Longest side the image is drawn at, in points.
    let pointSize: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: DecodedThumbnail?

    private var maxPixelSize: Int {
        ThumbnailCache.bucket(for: pointSize * displayScale)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let thumbnail {
                Image(decorative: thumbnail.cgImage, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: "\(url.path)#\(maxPixelSize)") {
            if let hit = ThumbnailCache.shared.cached(url, maxPixelSize: maxPixelSize) {
                thumbnail = hit
            } else {
                thumbnail = await ThumbnailCache.shared.load(url, maxPixelSize: maxPixelSize)
            }
        }
    }
}
