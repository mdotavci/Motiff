import Foundation

/// One row of a Recipe card. The full prompt is these parts joined in order.
struct RecipePart: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: RecipePartKind
    var text: String
}
