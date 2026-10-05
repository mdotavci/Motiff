import CoreGraphics
import Foundation

/// A board (or part of it) written out for an AI: one markdown text with every idea, prompt,
/// note and link, and the pictures numbered in the order the text names them, so they can be
/// attached alongside it. Copy for AI copies the text; Export for AI writes the text and the
/// pictures to a folder.
struct AIPack: Equatable {
    struct Picture: Equatable {
        let number: Int
        /// In the media folder.
        let filename: String
        let caption: String

        /// Its name in an exported folder: `images/03.png`.
        var exportName: String {
            let ext = (filename as NSString).pathExtension
            return String(format: "%02d", number) + (ext.isEmpty ? "" : ".\(ext)")
        }
    }

    let title: String
    let markdown: String
    let pictures: [Picture]

    /// What the pack says first, before the board: from Settings › AI pack.
    static let instructionKey = "aiPack.instruction"

    /// - Parameters:
    ///   - only: just these nodes and everything attached to them; nil for the whole board.
    ///   - instruction: a line for the AI to read first ("You are my creative director…").
    @MainActor
    static func make(from canvas: Canvas, only ids: Set<UUID>? = nil, instruction: String = "") -> AIPack {
        var builder = Builder()
        let live = canvas.nodes.filter { !$0.isDeleted }
        let included: Set<UUID>? = ids.map { ids in
            var all = ids
            for node in live where ids.contains(node.id) { all.formUnion(node.descendants.map(\.id)) }
            return all
        }
        func isIn(_ node: CanvasNode) -> Bool { included?.contains(node.id) ?? true }

        builder.line("# \(canvas.displayTitle)")
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstruction.isEmpty {
            builder.blank()
            builder.line(trimmedInstruction)
        }

        // Ideas with what belongs to them, in mind-map order.
        for root in canvas.roots where !root.isDeleted {
            builder.write(root, depth: 0, isIn: isIn)
        }

        // Then everything loose, top to bottom, left to right, as it sits on the board.
        let loose = canvas.unattachedNodes.filter { !$0.isDeleted }.sorted(by: Self.readingOrder)
        if loose.contains(where: { isIn($0) || $0.descendants.contains(where: isIn) }) {
            builder.blank()
            builder.line("## On the board")
            for node in loose {
                builder.write(node, depth: 1, isIn: isIn)
            }
        }

        // Links between things, which the headings don't show.
        let links = canvas.links.filter { link in
            guard !link.isDeleted, let from = link.from, let to = link.to else { return false }
            return isIn(from) && isIn(to)
        }
        if !links.isEmpty {
            builder.blank()
            builder.line("## Connections")
            for link in links {
                guard let from = link.from, let to = link.to else { continue }
                let label = link.label.map { " (\($0))" } ?? ""
                builder.line("- \(from.displayTitle) → \(to.displayTitle)\(label)")
            }
        }

        return AIPack(title: canvas.displayTitle, markdown: builder.text, pictures: builder.pictures)
    }

    /// A name a file system takes: no slashes or colons.
    static func safeName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Board" : cleaned
    }

    /// Rows about a node high apart, then left to right.
    @MainActor
    static func readingOrder(_ a: CanvasNode, _ b: CanvasNode) -> Bool {
        let rowA = (a.y / 200).rounded(.down)
        let rowB = (b.y / 200).rounded(.down)
        return rowA == rowB ? a.x < b.x : rowA < rowB
    }

    private struct Builder {
        var lines: [String] = []
        var pictures: [Picture] = []

        var text: String { lines.joined(separator: "\n") + "\n" }

        mutating func line(_ text: String) { lines.append(text) }

        mutating func blank() {
            if lines.last?.isEmpty == false { lines.append("") }
        }

        /// A node, then what belongs to it. Ideas are headings; everything else sits under the
        /// nearest one. Nodes outside the selection are skipped, but their children still count.
        @MainActor
        mutating func write(_ node: CanvasNode, depth: Int, isIn: (CanvasNode) -> Bool) {
            if isIn(node), !node.isLine {
                entry(for: node, depth: depth)
            }
            for child in node.sortedChildren where !child.isDeleted {
                write(child, depth: depth + 1, isIn: isIn)
            }
        }

        @MainActor
        private mutating func entry(for node: CanvasNode, depth: Int) {
            switch node.kind {
            case .idea:
                blank()
                line(String(repeating: "#", count: min(depth + 2, 4)) + " " + node.displayTitle)
                if let body = node.body?.trimmed, !body.isEmpty { line(body) }
            case .prompt:
                guard let reference = node.reference else { return }
                blank()
                let model = reference.model.map { " for \($0)" } ?? ""
                line("**Prompt\(model)**")
                line("```")
                line(reference.promptToCopy ?? "")
                line("```")
                for variant in reference.promptVariants where !variant.trimmed.isEmpty {
                    line("Another version:")
                    line("```")
                    line(reference.promptSettings.formatted(variant, model: reference.model))
                    line("```")
                }
                for field in reference.promptSettings.custom where !field.value.isEmpty {
                    line("- \(field.key): \(field.value)")
                }
                if reference.hasMedia { picture(reference, note: "its result") }
                about(reference)
            case .reference:
                guard let reference = node.reference else { return }
                blank()
                picture(reference, note: nil)
                if let prompt = reference.promptToCopy {
                    line("Made with: `\(prompt)`")
                }
                about(reference)
            case .note, .sticky, .text:
                guard let body = node.body?.trimmed, !body.isEmpty else { return }
                blank()
                line(node.kind == .text ? body : body.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
            case .shape:
                guard let label = node.body?.trimmed, !label.isEmpty else { return }
                line("- \(label)")
            case .link:
                let title = node.displayTitle
                line(node.urlString.map { "- [\(title)](\($0))" } ?? "- \(title)")
            }
        }

        /// A numbered picture, named in the text where it belongs.
        private mutating func picture(_ reference: Reference, note: String?) {
            let number = pictures.count + 1
            pictures.append(Picture(number: number, filename: reference.mediaFilename, caption: reference.caption))
            let extra = note.map { ", \($0)" } ?? ""
            line("[Image \(number)\(extra): \(reference.caption)]")
        }

        /// Why it was kept, and notes on it.
        @MainActor
        private mutating func about(_ reference: Reference) {
            if !reference.why.isEmpty {
                line("Why: " + reference.why.map(\.label).joined(separator: ", ")
                    + (reference.whyNote.map { " (\($0))" } ?? ""))
            }
            if let notes = reference.notes?.trimmed, !notes.isEmpty {
                line(notes)
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
