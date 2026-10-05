import Foundation

/// A prompt's details beyond its text: the usual ones (negative prompt, aspect ratio, seed,
/// parameters) and any of your own, in the order you added them. Stored in
/// `Reference.settings` (a string dictionary), with the order under `orderKey`, so libraries
/// from before keep their settings.
struct PromptSettings: Equatable, Sendable {
    struct Field: Equatable, Identifiable, Sendable {
        var key: String
        var value: String
        var id: String { key }
    }

    /// The details every prompt offers, in this order.
    enum Known: String, CaseIterable, Sendable {
        case negative = "Negative prompt"
        case aspect = "Aspect ratio"
        case seed = "Seed"
        case parameters = "Parameters"

        var placeholder: String {
            switch self {
            case .negative: "What to leave out"
            case .aspect: "4:5"
            case .seed: "1234"
            case .parameters: "--stylize 250, steps 30…"
            }
        }
    }

    /// Where the order of your own fields is kept in the dictionary.
    static let orderKey = "_order"

    /// The usual details, by name.
    var known: [Known: String] = [:]
    /// Your own, in order.
    var custom: [Field] = []

    init(known: [Known: String] = [:], custom: [Field] = []) {
        self.known = known
        self.custom = custom
    }

    init(_ dictionary: [String: String]) {
        for key in Known.allCases {
            if let value = dictionary[key.rawValue], !value.isEmpty { known[key] = value }
        }
        let knownKeys = Set(Known.allCases.map(\.rawValue))
        let others = dictionary.keys.filter { $0 != Self.orderKey && !knownKeys.contains($0) }
        let saved = dictionary[Self.orderKey]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        // Saved order first, then anything it doesn't name (from before there was an order).
        let ordered = saved.filter { others.contains($0) } + others.filter { !saved.contains($0) }.sorted()
        custom = ordered.map { Field(key: $0, value: dictionary[$0] ?? "") }
    }

    var dictionary: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in known where !value.isEmpty {
            result[key.rawValue] = value
        }
        let fields = custom.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        for field in fields {
            result[field.key] = field.value
        }
        if !fields.isEmpty, let order = try? JSONEncoder().encode(fields.map(\.key)) {
            result[Self.orderKey] = String(decoding: order, as: UTF8.self)
        }
        return result
    }

    /// A name for a new field of your own that isn't taken yet.
    func newFieldName() -> String {
        let taken = Set(custom.map(\.key) + Known.allCases.map(\.rawValue))
        var name = "Field"
        var number = 2
        while taken.contains(name) {
            name = "Field \(number)"
            number += 1
        }
        return name
    }

    // MARK: Copying

    /// Models people write prompts for, offered as suggestions.
    static let suggestedModels = [
        "Midjourney", "DALL·E", "Flux", "Stable Diffusion", "Ideogram", "Firefly",
        "Claude", "ChatGPT", "Gemini", "Runway", "Sora",
    ]

    /// The prompt as that model takes it: Midjourney gets `--ar`, `--seed` and `--no` after the
    /// text; Stable Diffusion and Flux get the negative prompt on its own line; parameters are
    /// added as written. Anything else gets the text alone.
    func formatted(_ prompt: String, model: String?) -> String {
        let model = (model ?? "").lowercased()
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.contains("midjourney") {
            if let aspect = known[.aspect], !aspect.isEmpty, !text.contains("--ar") { text += " --ar \(aspect)" }
            if let seed = known[.seed], !seed.isEmpty, !text.contains("--seed") { text += " --seed \(seed)" }
            if let negative = known[.negative], !negative.isEmpty, !text.contains("--no") { text += " --no \(negative)" }
            if let parameters = known[.parameters], !parameters.isEmpty { text += " \(parameters)" }
        } else if model.contains("stable diffusion") || model.contains("flux") || model.contains("sdxl") {
            if let parameters = known[.parameters], !parameters.isEmpty { text += "\n\(parameters)" }
            if let negative = known[.negative], !negative.isEmpty { text += "\nNegative prompt: \(negative)" }
        }
        return text
    }
}

extension Reference {
    var promptSettings: PromptSettings {
        get { PromptSettings(settings) }
        set { settings = newValue.dictionary }
    }

    /// The prompt to paste into its model: the text with the model's own parameters
    /// (`PromptSettings.formatted`). Nil when there's no prompt.
    var promptToCopy: String? {
        copyablePrompt.map { promptSettings.formatted($0, model: model) }
    }
}
