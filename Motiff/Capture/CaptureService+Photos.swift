#if os(iOS)
import PhotosUI
import SwiftUI

extension CaptureService {
    /// Photos and videos picked with `PhotosPicker`, read as data with their type.
    static func items(from photos: [PhotosPickerItem]) async -> [CaptureItem] {
        var captured: [CaptureItem] = []
        for photo in photos {
            guard let type = photo.supportedContentTypes.first,
                  let data = try? await photo.loadTransferable(type: Data.self)
            else { continue }
            captured.append(.imageData(data, type))
        }
        return captured
    }
}
#endif
