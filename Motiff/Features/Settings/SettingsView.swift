import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("App Group", value: AppGroup.isAvailable ? "Connected" : "Not available")
                } header: {
                    Text("Storage")
                } footer: {
                    if !AppGroup.isAvailable {
                        Text("Check signing and the App Group capability. Using local storage for now.")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
