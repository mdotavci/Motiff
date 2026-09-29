import Foundation

enum MediaType: String, Codable, CaseIterable {
    case image, gif, video
}

/// Where a Reference came from. Shown as one letter on its thumbnail.
enum Origin: String, Codable, CaseIterable {
    case found, generated, mine, remix

    var letter: String {
        switch self {
        case .found: "F"
        case .generated: "G"
        case .mine: "M"
        case .remix: "R"
        }
    }

    /// The full word, for VoiceOver and menus.
    var label: String {
        switch self {
        case .found: "Found"
        case .generated: "Generated"
        case .mine: "Mine"
        case .remix: "Remix"
        }
    }
}

enum ReferenceStatus: String, Codable, CaseIterable {
    case keep, maybe, reject
}

/// Progress of the background Claude read for a Reference.
enum AIState: String, Codable, CaseIterable {
    case pending, done, failed
}

/// One reason a Reference was kept. Tap a chip, or write a line instead (`Reference.whyNote`).
enum WhyChip: String, Codable, CaseIterable {
    case type, color, layout, light, texture, motion, mood, idea

    var label: String { rawValue.capitalized }

    /// The Recipe part this reason points at, if there is one.
    var recipePartKind: RecipePartKind? {
        switch self {
        case .color: .color
        case .layout: .composition
        case .light: .light
        case .texture: .texture
        case .mood: .mood
        case .type, .motion, .idea: nil
        }
    }
}

/// What a prompt is for. Nil on References that aren't prompts.
enum PromptPurpose: String, Codable, CaseIterable {
    /// Image and video generation.
    case image
    /// Writing, editing, rewriting.
    case text
    /// App and dev prompts, e.g. for Claude Code.
    case code
    case other

    var label: String {
        switch self {
        case .image: "Image"
        case .text: "Text"
        case .code: "Code"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "ellipsis"
        }
    }
}

/// A row in a Recipe card. Order here is the order shown in the card.
enum RecipePartKind: String, Codable, CaseIterable {
    case subject, composition, light, camera, material, color, texture, style, mood, params

    var label: String {
        switch self {
        case .subject: "Subject"
        case .composition: "Composition"
        case .light: "Light"
        case .camera: "Camera"
        case .material: "Material"
        case .color: "Color"
        case .texture: "Texture"
        case .style: "Style"
        case .mood: "Mood"
        case .params: "Params"
        }
    }
}
