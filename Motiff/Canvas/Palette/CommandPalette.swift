import SwiftUI

/// One thing the ⌘K palette can go to or do.
struct PaletteItem: Identifiable {
    enum Kind: Int {
        case action, canvas, node, reference
    }

    let id: String
    let kind: Kind
    let title: String
    /// What it is and where: "Idea · Product photography look".
    let subtitle: String
    let systemImage: String
    /// The shortcut, for actions.
    var keys: String = ""
    let run: @MainActor () -> Void
}

/// ⌘K: type to go to a Canvas, an Idea or card on any Canvas, a Reference, or to run an action.
/// ↑ ↓ choose, Return goes, Esc closes.
struct CommandPalette: View {
    let items: [PaletteItem]
    let close: () -> Void

    @State private var query = ""
    @State private var chosen = 0
    @FocusState private var focused: Bool

    static let limit = 30

    var body: some View {
        let results = Self.rank(items, for: query)
        VStack(spacing: 0) {
            HStack(spacing: Theme.unit) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Go to a Canvas, Idea or Reference, or do something", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { run(results) }
                    .onKeyPress(.downArrow) {
                        chosen = min(chosen + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        chosen = max(chosen - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
            }
            .padding(.horizontal, Theme.gutter)
            .frame(height: 48)

            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                PaletteRow(item: item, isChosen: index == chosen)
                                    .id(item.id)
                                    .onTapGesture {
                                        chosen = index
                                        run(results)
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: chosen) { _, index in
                        if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                    }
                }
            } else if !query.isEmpty {
                Divider()
                Text("Nothing matches “\(query)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.gutter)
            }
        }
        .frame(width: 580)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .onChange(of: query) { chosen = 0 }
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(chosen) else { return }
        let item = results[chosen]
        close()
        item.run()
    }

    /// With nothing typed: the actions, then Canvases. Otherwise the best matches on title (or,
    /// less, on where it is), actions and Canvases first on a tie.
    static func rank(_ items: [PaletteItem], for query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return Array(items.filter { $0.kind == .action || $0.kind == .canvas }.prefix(limit))
        }
        let scored = items.compactMap { item -> (item: PaletteItem, score: Int)? in
            let title = FuzzyMatch.score(trimmed, in: item.title)
            let subtitle = FuzzyMatch.score(trimmed, in: item.subtitle).map { $0 - 8 }
            guard let best = [title, subtitle].compactMap({ $0 }).max() else { return nil }
            return (item, best)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.kind.rawValue < $1.item.kind.rawValue }
            .prefix(limit)
            .map(\.item)
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isChosen: Bool

    var body: some View {
        HStack(spacing: Theme.unit * 1.5) {
            Image(systemName: item.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.unit)
            if !item.keys.isEmpty {
                Text(item.keys)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(isChosen ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if isChosen {
                RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 2).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
    }
}
