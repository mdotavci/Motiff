import SwiftUI

/// Asked right after saving: why keep this? Chips and a line, applied to everything just saved.
/// Skipping is fine; it can be filled in later.
struct WhySheet: View {
    let references: [Reference]

    @Environment(\.dismiss) private var dismiss
    @State private var chips: [WhyChip] = []
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 2) {
            HStack(alignment: .top, spacing: Theme.unit * 1.5) {
                ForEach(references.prefix(4)) { reference in
                    Group {
                        if reference.hasMedia {
                            ThumbnailImage(url: reference.mediaURL, pointSize: 64)
                        } else {
                            TypographicCover(text: reference.copyablePrompt ?? "")
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(references.count == 1 ? "Saved" : "Saved \(references.count)")
                        .font(.headline)
                    Text("Why keep \(references.count == 1 ? "it" : "them")?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            WhyChipToggles(selected: chips) { chip in
                if let index = chips.firstIndex(of: chip) { chips.remove(at: index) } else { chips.append(chip) }
            }

            TextField("Or in a line", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Skip") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.gutter * 1.5)
        .frame(width: 420)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        for reference in references {
            var why = reference.why
            for chip in chips where !why.contains(chip) { why.append(chip) }
            reference.why = why
            if !trimmed.isEmpty { reference.whyNote = trimmed }
        }
        try? references.first?.modelContext?.save()
        dismiss()
    }
}
