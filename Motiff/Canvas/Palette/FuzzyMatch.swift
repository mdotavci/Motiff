import Foundation

/// Typing a few letters of something to find it: "prdlk" finds "Product photography look".
/// The query's letters must appear in order; runs of letters next to each other and letters at
/// the start of a word count for more, and shorter texts win ties.
enum FuzzyMatch {
    /// Higher is better; nil when the text doesn't contain the query's letters in order.
    static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.searchFolded().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(text.searchFolded())
        var score = 0
        var matched = 0
        var previous = -2
        for (index, character) in haystack.enumerated() where matched < needle.count {
            guard character == needle[matched] else { continue }
            var points = 1
            if index == previous + 1 { points += 5 }
            if index == 0 {
                points += 10
            } else if !haystack[index - 1].isLetter && !haystack[index - 1].isNumber {
                points += 6
            }
            score += points
            previous = index
            matched += 1
        }
        guard matched == needle.count else { return nil }
        return score - haystack.count / 10
    }
}

extension String {
    /// Lowercased with accents taken off, for matching what people type.
    func searchFolded() -> String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
