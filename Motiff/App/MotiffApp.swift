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
    }
}
