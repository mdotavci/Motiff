import Foundation

/// Guesses what a pasted prompt is for from how it's written: Midjourney-style parameters and
/// camera words mean Image, code fences and programming words mean Code, anything else Text.
/// A guess, not a rule; the inspector changes it.
enum PromptPurposeGuess {
    /// Parameters only image generators take. One is enough.
    private static let imageParameters = ["--ar ", "--v ", "--style ", "--stylize ", "--chaos ", "--niji", "--q ", "--seed "]

    private static let imageWords = [
        "photo of", "photograph of", "portrait of", "illustration of", "render of", "cinematic",
        "8k", "4k", "35mm", "50mm", "85mm", "bokeh", "depth of field", "studio lighting",
        "soft lighting", "golden hour", "octane", "unreal engine", "midjourney", "dall-e",
        "stable diffusion", "aspect ratio", "wide shot", "close-up",
    ]

    private static let codeWords = [
        "func ", "function", "const ", "def ", "=>", "</", "#include", "npm ", "git ", "swiftui",
        "swift ", "typescript", "javascript", "python", "refactor", "unit test", "endpoint",
        "claude code", "repository", "pull request", "stack trace", "compile", "bug in",
    ]

    static func guess(_ text: String) -> PromptPurpose {
        let lower = text.lowercased()
        if lower.contains("```") { return .code }
        if imageParameters.contains(where: { lower.contains($0) }) { return .image }

        let image = imageWords.filter { lower.contains($0) }.count
        // Lines that end like code count too.
        let codeLines = lower.split(whereSeparator: \.isNewline).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed == "}"
        }.count
        let code = codeWords.filter { lower.contains($0) }.count + codeLines

        if code > image { return .code }
        if image > 0 { return .image }
        return .text
    }
}
