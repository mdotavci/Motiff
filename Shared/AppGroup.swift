import Foundation

/// Where Motiff keeps its library on disk.
///
/// iOS: the App Group container, shared by the app and the Share Extension.
/// macOS: the app's own sandbox container for now. The Mac Share Extension step moves it
/// into an App Group, which on the Mac needs your Team ID.
enum AppGroup {
    static let identifier = "group.com.mdotavci.motiff"

    /// False when the App Group entitlement is missing (e.g. signing not set up).
    static var isAvailable: Bool {
        #if os(macOS)
        false
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
        #endif
    }

    static var containerURL: URL {
        #if os(macOS)
        URL.applicationSupportDirectory.appending(path: "Motiff", directoryHint: .isDirectory)
        #else
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.applicationSupportDirectory
        #endif
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
