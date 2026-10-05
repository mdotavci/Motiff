import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns pasted image data into a file worth keeping: TIFF (what many apps put on the Mac
/// clipboard, screenshots included) becomes PNG, a fraction of the size.
enum ImageConversion {
    /// The data and type to store for pasted `data` of `type`: PNG for TIFF, as is otherwise.
    static func storable(_ data: Data, type: UTType) -> (data: Data, type: UTType) {
        guard type.conforms(to: .tiff), let png = pngData(from: data) else { return (data, type) }
        return (png, .png)
    }

    /// The first image in `data`, as PNG. Nil if it isn't an image ImageIO can read.
    static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
