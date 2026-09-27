import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    var body: some View {
        #if os(macOS)
        form
            .formStyle(.grouped)
            .frame(width: 480, height: 200)
        #else
        NavigationStack {
            form.navigationTitle("Settings")
        }
        #endif
    }

    private var form: some View {
        Form {
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
