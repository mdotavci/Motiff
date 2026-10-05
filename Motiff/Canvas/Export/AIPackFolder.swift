import SwiftUI
import UniformTypeIdentifiers

/// Export for AI: a folder holding the pack's text as `<Board>.md` and its pictures as
/// `images/01.png…`, numbered as the text names them. Drag the folder into a chat, or upload it.
struct AIPackFolder: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    let pack: AIPack
    /// Where the pictures' files are, by filename.
    let mediaURL: @Sendable (String) -> URL

    init(pack: AIPack, mediaURL: @escaping @Sendable (String) -> URL) {
        self.pack = pack
        self.mediaURL = mediaURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var files: [String: FileWrapper] = [:]
        let text = FileWrapper(regularFileWithContents: Data(pack.markdown.utf8))
        text.preferredFilename = AIPack.safeName(pack.title) + ".md"
        files[text.preferredFilename ?? "Board.md"] = text

        var images: [String: FileWrapper] = [:]
        for picture in pack.pictures {
            guard let data = try? Data(contentsOf: mediaURL(picture.filename)) else { continue }
            let file = FileWrapper(regularFileWithContents: data)
            file.preferredFilename = picture.exportName
            images[picture.exportName] = file
        }
        if !images.isEmpty {
            let folder = FileWrapper(directoryWithFileWrappers: images)
            folder.preferredFilename = "images"
            files["images"] = folder
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }
}
