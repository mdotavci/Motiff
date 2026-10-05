import Foundation

/// The formatting bar's buttons as plain text edits on markdown: wrap the selection in `**`,
/// put `# ` before its lines, and so on. Offsets are in Characters; each edit returns the new
/// text and what to select afterwards.
enum MarkdownFormat: CaseIterable, Sendable {
    case bold, italic, heading, bullet, checklist, link

    var label: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .heading: "Heading"
        case .bullet: "Bulleted List"
        case .checklist: "Checklist"
        case .link: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .heading: "textformat.size.larger"
        case .bullet: "list.bullet"
        case .checklist: "checklist"
        case .link: "link"
        }
    }

    struct Edit: Equatable {
        let text: String
        /// What to select after: character offsets, `start..<end`.
        let start: Int
        let end: Int
    }

    func apply(to text: String, start: Int, end: Int) -> Edit {
        let characters = Array(text)
        let start = min(max(start, 0), characters.count)
        let end = min(max(end, start), characters.count)
        switch self {
        case .bold: return Self.wrap(characters, start, end, with: "**")
        case .italic: return Self.wrap(characters, start, end, with: "_")
        case .heading: return Self.prefixLines(characters, start, end, with: "# ")
        case .bullet: return Self.prefixLines(characters, start, end, with: "- ")
        case .checklist: return Self.prefixLines(characters, start, end, with: "- [ ] ")
        case .link: return Self.link(characters, start, end)
        }
    }

    /// `**text**`; already wrapped, it unwraps. With nothing selected, the cursor lands between.
    private static func wrap(_ text: [Character], _ start: Int, _ end: Int, with marker: String) -> Edit {
        let mark = Array(marker)
        let before = Array(text[max(0, start - mark.count)..<start])
        let after = Array(text[end..<min(text.count, end + mark.count)])
        if before == mark, after == mark {
            var result = text
            result.removeSubrange(end..<end + mark.count)
            result.removeSubrange(start - mark.count..<start)
            return Edit(text: String(result), start: start - mark.count, end: end - mark.count)
        }
        var result = text
        result.insert(contentsOf: mark, at: end)
        result.insert(contentsOf: mark, at: start)
        return Edit(text: String(result), start: start + mark.count, end: end + mark.count)
    }

    /// `# ` in front of every line the selection touches; if they all have it, it comes off.
    private static func prefixLines(_ text: [Character], _ start: Int, _ end: Int, with prefix: String) -> Edit {
        let mark = Array(prefix)
        var lineStarts: [Int] = []
        var index = start
        while index > 0, text[index - 1] != "\n" { index -= 1 }
        lineStarts.append(index)
        if end > start {
            for position in start..<end where text[position] == "\n" && position + 1 < text.count {
                lineStarts.append(position + 1)
            }
        }
        let hasAll = lineStarts.allSatisfy { Array(text[$0..<min(text.count, $0 + mark.count)]) == mark }
        var result = text
        var shift = 0
        var startShift = 0
        for (number, lineStart) in lineStarts.enumerated() {
            let at = lineStart + shift
            if hasAll {
                result.removeSubrange(at..<at + mark.count)
                shift -= mark.count
            } else {
                result.insert(contentsOf: mark, at: at)
                shift += mark.count
            }
            if number == 0 { startShift = shift }
        }
        let newStart = max(lineStarts[0], start + startShift)
        return Edit(text: String(result), start: newStart, end: max(newStart, end + shift))
    }

    /// `[text](https://)` with the address selected, ready to type over.
    private static func link(_ text: [Character], _ start: Int, _ end: Int) -> Edit {
        let label = start == end ? Array("link") : Array(text[start..<end])
        let address = Array("https://")
        let inserted = Array("[") + label + Array("](") + address + Array(")")
        var result = text
        result.replaceSubrange(start..<end, with: inserted)
        let addressStart = start + 1 + label.count + 2
        return Edit(text: String(result), start: addressStart, end: addressStart + address.count)
    }
}
