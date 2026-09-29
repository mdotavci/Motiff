import Foundation

/// Reads and writes the original media files for References.
///
/// Files live in `AppGroup.mediaURL`, named by a UUID plus their original extension.
/// SwiftData stores only the filename, never the bytes.
enum MediaStore {
    enum StoreError: Error {
        case writeFailed
    }

    /// Copies `data` into the Media folder under a new filename and returns that filename.
    @discardableResult
    static func store(_ data: Data, fileExtension: String) throws -> String {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let url = AppGroup.mediaURL.appending(path: filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.writeFailed
        }
        return filename
    }

    static func url(for filename: String) -> URL {
        AppGroup.mediaURL.appending(path: filename)
    }

    static func delete(_ filename: String) {
        // An empty name would point at the Media folder itself.
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
