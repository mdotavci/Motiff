import SwiftUI

/// The help sheet (⌘/): every shortcut, grouped, keys on the right.
struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.gutter)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.unit * 3) {
                    ForEach(ShortcutCatalog.sections) { section in
                        VStack(alignment: .leading, spacing: Theme.unit) {
                            Text(section.title).motiffLabel()
                            ForEach(section.items) { item in
                                ShortcutRow(shortcut: item)
                            }
                        }
                    }
                }
                .padding(Theme.gutter)
            }
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520, idealHeight: 640)
    }
}

private struct ShortcutRow: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.unit) {
            Text(shortcut.title)
                .font(.callout)
            Spacer(minLength: Theme.unit)
            if shortcut.pointer != nil {
                Text(shortcut.keys)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(shortcut.keys)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ShortcutHelpView()
}
