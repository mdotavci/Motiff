import AVFoundation
import Foundation
import ImageIO
import LinkPresentation
import SwiftData
import UniformTypeIdentifiers

/// Something brought into Motiff by drag and drop, paste or File › Import, before it's anything.
enum CaptureItem: Sendable {
    /// A file from Finder or the import panel.
    case file(URL)
    /// Image bytes, e.g. an image dragged out of a browser.
    case imageData(Data, UTType)
    /// A web address: an image to download, or a page to become a Link card.
    case webURL(URL)
    /// Text: a prompt, or a web address written out.
    case text(String)
}

/// A capture with the slow work done (media copied into the Media folder and measured, link
/// titles fetched), ready to become a Reference or a Link card all at once: one Undo step.
enum PreparedCapture: Sendable {
    case media(filename: String, type: MediaType, width: Int, height: Int, source: URL?)
    case prompt(String)
    case link(url: URL, title: String?, iconFilename: String?)
}

/// Turns drops, pastes and imports into References (and, on a Canvas, Link cards).
/// The Library and the Canvas share it.
@MainActor
enum CaptureService {
    /// What Motiff accepts from a drag or the pasteboard.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .movie, .url, .plainText]

    // MARK: Reading what came in

    static func items(from providers: [NSItemProvider]) async -> [CaptureItem] {
        var items: [CaptureItem] = []
        for provider in providers {
            if let item = await item(from: provider) { items.append(item) }
        }
        return items
    }

    /// One provider's best item: a file, else image bytes, else a URL, else text.
    private static func item(from provider: NSItemProvider) async -> CaptureItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let data = await data(from: provider, type: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return .file(url)
        }
        if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
           let data = await data(from: provider, type: type) {
            return .imageData(data, type)
        }
        if provider.canLoadObject(ofClass: URL.self), let url = await url(from: provider) {
            return url.isFileURL ? .file(url) : .webURL(url)
        }
        if provider.canLoadObject(ofClass: String.self), let text = await text(from: provider) {
            return .text(text)
        }
        return nil
    }

    // The callbacks below run on a background queue, so they're @Sendable (not main-actor) and
    // only hand their result to the continuation.

    private static func data(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { @Sendable data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { @Sendable text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    // MARK: Making References

    /// The Reference for a prepared capture, inserted into `context`. Nil for a link: only a
    /// Canvas holds those, as Link cards.
    ///
    /// Media comes in as Found (it's from somewhere else); text comes in as a prompt of your own,
    /// with its purpose guessed from how it's written.
    static func makeReference(_ prepared: PreparedCapture, in context: ModelContext) -> Reference? {
        switch prepared {
        case let .media(filename, type, width, height, source):
            let reference = Reference(mediaFilename: filename, mediaType: type, width: width, height: height, origin: .found)
            context.insert(reference)
            if let source {
                reference.sourceURL = source.absoluteString
                reference.sourcePlatform = source.host()
            }
            return reference
        case .prompt(let text):
            let reference = Reference(mediaFilename: "", mediaType: .image, width: 0, height: 0, origin: .mine)
            context.insert(reference)
            reference.promptRaw = text
            reference.purpose = PromptPurposeGuess.guess(text)
            return reference
        case .link:
            return nil
        }
    }
}

// MARK: - Preparing

/// The slow part of a capture: copying, downloading, measuring, fetching link titles.
/// Runs off the main actor where it can.
enum CapturePrep {
    static func prepare(_ items: [CaptureItem]) async -> [PreparedCapture] {
        var prepared: [PreparedCapture] = []
        for item in items {
            if let result = await prepare(item) { prepared.append(result) }
        }
        return prepared
    }

    static func prepare(_ item: CaptureItem) async -> PreparedCapture? {
        switch item {
        case .file(let url):
            return await prepareFile(url)
        case let .imageData(data, type):
            return await storeMedia(data, type: type, source: nil)
        case .webURL(let url):
            return await prepareWeb(url)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
               let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return await prepareWeb(url)
            }
            return .prompt(trimmed)
        }
    }

    /// Image, GIF or video; nil for anything Motiff doesn't keep.
    static func mediaType(for type: UTType) -> MediaType? {
        if type.conforms(to: .gif) { return .gif }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        return nil
    }

    private static func prepareFile(_ url: URL) async -> PreparedCapture? {
        let fileExtension = url.pathExtension.lowercased()
        guard let type = UTType(filenameExtension: fileExtension), let mediaType = mediaType(for: type) else {
            return nil
        }
        // Files from the import panel are security scoped; dropped ones may not be.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let filename = try? MediaStore.copy(from: url, fileExtension: fileExtension) else { return nil }
        let size = await mediaSize(of: MediaStore.url(for: filename), type: mediaType)
        return .media(filename: filename, type: mediaType, width: size.width, height: size.height, source: nil)
    }

    private static func storeMedia(_ data: Data, type: UTType, source: URL?) async -> PreparedCapture? {
        guard let mediaType = mediaType(for: type),
              let filename = try? MediaStore.store(data, fileExtension: type.preferredFilenameExtension ?? "png")
        else { return nil }
        let size = await mediaSize(of: MediaStore.url(for: filename), type: mediaType)
        return .media(filename: filename, type: mediaType, width: size.width, height: size.height, source: source)
    }

    /// An address that names an image is downloaded; any other page becomes a Link card.
    private static func prepareWeb(_ url: URL) async -> PreparedCapture? {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), mediaType(for: type) != nil,
           let result = try? await URLSession.shared.data(from: url),
           let mime = result.1.mimeType, let downloaded = UTType(mimeType: mime), mediaType(for: downloaded) != nil {
            return await storeMedia(result.0, type: downloaded, source: url)
        }
        let metadata = await LinkMetadata.fetch(url)
        let iconFilename = metadata.icon.flatMap { try? MediaStore.store($0, fileExtension: "png") }
        return .link(url: url, title: metadata.title, iconFilename: iconFilename)
    }

    /// Pixel size, upright (EXIF rotation applied). Zero if it can't be read.
    static func mediaSize(of url: URL, type: MediaType) async -> (width: Int, height: Int) {
        if type == .video {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let loaded = try? await track.load(.naturalSize, .preferredTransform)
            else { return (0, 0) }
            let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return (0, 0) }
        // Orientations 5–8 are turned a quarter, so the sides swap.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }
}

/// A page's title and icon, via LinkPresentation.
@MainActor
private enum LinkMetadata {
    /// Holds the provider until it answers; it's only touched by its own callback.
    private final class Request: @unchecked Sendable {
        let provider = LPMetadataProvider()
    }

    static func fetch(_ url: URL) async -> (title: String?, icon: Data?) {
        let request = Request()
        request.provider.timeout = 8
        return await withCheckedContinuation { continuation in
            request.provider.startFetchingMetadata(for: url) { @Sendable metadata, _ in
                withExtendedLifetime(request) {}
                let title = metadata?.title
                guard let icon = metadata?.iconProvider else {
                    continuation.resume(returning: (title, nil))
                    return
                }
                _ = icon.loadDataRepresentation(for: .image) { @Sendable data, _ in
                    continuation.resume(returning: (title, data))
                }
            }
        }
    }
}
