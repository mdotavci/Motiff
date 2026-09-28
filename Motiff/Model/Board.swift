import Foundation
import SwiftData

/// A Reference can live on many Boards. Boards are grids, not folders.
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
