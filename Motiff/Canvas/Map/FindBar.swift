import SwiftUI

/// ⌘F: a field over the Canvas. Matches stay at full strength, the rest dims. Return or ⌘G
/// goes to the next match, ⇧Return to the previous; Esc closes.
struct FindBar: View {
    let controller: CanvasController

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.unit) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find on this board", text: Binding(
                get: { controller.searchText },
                set: { controller.setSearchText($0) }
            ))
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { controller.findNext() }
            .onKeyPress(keys: [.return], phases: .down) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                controller.findNext(by: -1)
                return .handled
            }
            .onKeyPress(.escape) {
                controller.closeFind()
                return .handled
            }
            .frame(minWidth: 180)

            if !controller.searchText.isEmpty {
                Text(verbatim: countText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Previous", systemImage: "chevron.up") { controller.findNext(by: -1) }
                    .help("Previous (\(ShortcutCatalog.findPrevious.keys))")
                Button("Next", systemImage: "chevron.down") { controller.findNext() }
                    .help("Next (\(ShortcutCatalog.findNext.keys))")
            }
            Button("Close", systemImage: "xmark", action: controller.closeFind)
                .help("Close (esc)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .fixedSize()
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
    }

    private var countText: String {
        let count = controller.searchResults.count
        guard count > 0 else { return "No matches" }
        if let index = controller.searchIndex { return "\(index + 1) of \(count)" }
        return count == 1 ? "1 match" : "\(count) matches"
    }
}
