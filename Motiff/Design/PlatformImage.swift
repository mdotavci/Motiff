import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Loads an image file from disk into a resizable SwiftUI `Image`, on iOS or macOS.
struct PlatformImage: View {
    let url: URL

    var body: some View {
        if let image = Self.load(url) {
            image.resizable()
        } else {
            Rectangle().fill(.gray.opacity(0.2))
        }
    }

    private static func load(_ url: URL) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }
}
