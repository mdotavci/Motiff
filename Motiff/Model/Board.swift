import Foundation
import SwiftData

/// The first kind of board: a grid of References. Replaced by Canvases ("Boards" in the app),
/// which hold pictures, prompts and notes freely. Kept in the schema so old libraries open;
/// `SeedData.migrateBoardsIfNeeded` turns each one into a board once.
@Model
final class Board {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    @Relationship(inverse: \Reference.boards) var references: [Reference] = []

    init(name: String) {
        self.name = name
    }
}

extension Board {
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled board" : name
    }

    /// Newest first, like the Library.
    var sortedReferences: [Reference] {
        references.sorted { $0.createdAt > $1.createdAt }
    }
}
