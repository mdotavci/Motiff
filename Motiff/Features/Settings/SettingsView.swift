import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    /// What Copy and Export for AI put first.
    @AppStorage(AIPack.instructionKey) private var instruction = ""

    var body: some View {
        #if os(macOS)
        form
            .formStyle(.grouped)
            .frame(width: 480, height: 360)
        #else
        NavigationStack {
            form.navigationTitle("Settings")
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                TextField("Say this first", text: $instruction, prompt: Text("You are my creative director. Here's my board for a new campaign…"), axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("AI pack")
            } footer: {
                Text("Copy for AI and Export for AI start with this, then the board: its ideas, prompts with their models and settings, notes and numbered pictures.")
            }
            Section {
                #if os(macOS)
                LabeledContent("Library") {
                    Text(AppGroup.containerURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppGroup.containerURL])
                }
                #else
                LabeledContent("App Group", value: AppGroup.isAvailable ? "Connected" : "Not available")
                #endif
            } header: {
                Text("Storage")
            } footer: {
                #if os(iOS)
                if !AppGroup.isAvailable {
                    Text("Check signing and the App Group capability. Using local storage for now.")
                }
                #endif
            }
        }
    }
}
