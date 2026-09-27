import SwiftUI

@main
struct MotiffApp: App {
    init() {
        AppGroup.prepareDirectories()
        #if DEBUG
        print("Motiff: App Group \(AppGroup.isAvailable ? "connected" : "not available")")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
