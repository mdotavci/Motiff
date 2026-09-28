import Foundation

/// What Claude saw when it read a Reference's image: type, style, composition, palette,
/// typography, texture, lighting, mood. Written once in the background after save.
struct ReadTags: Codable, Hashable {
    var type: String?
    var style: String?
    var composition: String?
    var paletteHex: [String] = []
    var typography: String?
    var textureDescription: String?
    var lighting: String?
    var mood: String?
}
