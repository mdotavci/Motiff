import Foundation

/// Shared locations for the app and the Share Extension.
enum AppGroup {
    static let identifier = "group.com.mdotavci.motiff"

    /// False when the App Group entitlement is missing (e.g. signing not set up).
    /// We then fall back to the app's own Application Support folder so things still run.
    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.applicationSupportDirectory
    }

    /// Original media files, one per Reference.
    static var mediaURL: URL { containerURL.appending(path: "Media", directoryHint: .isDirectory) }

    /// Drop folder the Share Extension writes to; the app imports from here.
    static var incomingURL: URL { containerURL.appending(path: "Incoming", directoryHint: .isDirectory) }

    static func prepareDirectories() {
        for url in [mediaURL, incomingURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
