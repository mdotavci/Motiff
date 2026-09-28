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
