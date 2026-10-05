import SwiftUI

/// A text area for longer writing, with a formatting bar: Bold ⌘B, Italic ⌘I, Heading, list,
/// checklist, link. It writes markdown, so the same text shows formatted on cards. Changes are
/// kept a moment after typing stops and when it loses focus, so a paragraph is one Undo step.
struct MarkdownEditor: View {
    let value: String
    var prompt = "Write anything…"
    var minHeight: CGFloat = 180
    var font: Font = .body
    let commit: (String) -> Void

    @State private var draft = ""
    @State private var selection: TextSelection?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(MarkdownFormat.allCases, id: \.self) { format in
                    Button(format.label, systemImage: format.systemImage) { apply(format) }
                        .modifier(FormatShortcut(format: format))
                        .help(Self.help(for: format))
                }
                Spacer(minLength: 0)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 13))
            .padding(.horizontal, 6)
            .frame(height: 30)

            Divider()

            TextEditor(text: $draft, selection: $selection)
                .font(font)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(8)
                .frame(minHeight: minHeight)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(prompt)
                            .font(font)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in
            if !focused, newValue != draft { draft = newValue }
        }
        .onChange(of: draft) { _, text in
            guard text != value else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onChange(of: focused) { wasFocused, isFocused in
            if wasFocused, !isFocused { save() }
        }
        .onDisappear { save() }
    }

    private func save() {
        saveTask?.cancel()
        if draft != value { commit(draft) }
    }

    /// Runs a format on the selection (or the cursor), then selects what it says to.
    private func apply(_ format: MarkdownFormat) {
        var start = draft.count
        var end = draft.count
        if case let .selection(range)? = selection?.indices {
            start = draft.distance(from: draft.startIndex, to: range.lowerBound)
            end = draft.distance(from: draft.startIndex, to: range.upperBound)
        }
        let edit = format.apply(to: draft, start: start, end: end)
        draft = edit.text
        let lower = draft.index(draft.startIndex, offsetBy: edit.start)
        let upper = draft.index(draft.startIndex, offsetBy: edit.end)
        selection = TextSelection(range: lower..<upper)
        focused = true
    }

    private static func help(for format: MarkdownFormat) -> String {
        switch format {
        case .bold: "\(format.label) (\(ShortcutCatalog.bold.keys))"
        case .italic: "\(format.label) (\(ShortcutCatalog.italic.keys))"
        case .link: "\(format.label) (\(ShortcutCatalog.insertLink.keys))"
        case .heading, .bullet, .checklist: format.label
        }
    }
}

/// ⌘B, ⌘I and ⇧⌘K on the formatting bar's buttons.
private struct FormatShortcut: ViewModifier {
    let format: MarkdownFormat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch format {
        case .bold: content.shortcut(ShortcutCatalog.bold)
        case .italic: content.shortcut(ShortcutCatalog.italic)
        case .link: content.shortcut(ShortcutCatalog.insertLink)
        case .heading, .bullet, .checklist: content
        }
    }
}
