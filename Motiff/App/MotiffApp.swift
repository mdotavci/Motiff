import SwiftUI

@main
struct MotiffApp: App {
    init() {
        AppGroup.prepareDirectories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
