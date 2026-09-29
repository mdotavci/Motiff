import SwiftData
import SwiftUI

@main
struct MotiffApp: App {
    let container: ModelContainer

    init() {
        AppGroup.prepareDirectories()
        do {
            container = try ModelContainer(for: MotiffSchema.schema)
        } catch {
            fatalError("Could not create the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .task {
                    await MainActor.run {
                        SeedData.seedIfNeeded(context: container.mainContext)
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CanvasCommands()
            LibraryCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
