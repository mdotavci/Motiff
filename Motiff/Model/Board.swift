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

extension Board {
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled board" : name
    }

    /// Newest first, like the Library.
    var sortedReferences: [Reference] {
        references.sorted { $0.createdAt > $1.createdAt }
    }

    func contains(_ reference: Reference) -> Bool {
        references.contains { $0.id == reference.id }
    }

    @discardableResult
    static func make(name: String, in context: ModelContext) -> Board {
        let board = Board(name: name)
        context.insert(board)
        return board
    }

    /// Puts References on the Board; ones already on it stay once.
    func add(_ new: [Reference]) {
        for reference in new where !contains(reference) {
            references.append(reference)
        }
    }

    /// Takes a Reference off the Board. It stays in the Library and on its other Boards.
    func remove(_ reference: Reference) {
        references.removeAll { $0.id == reference.id }
    }

    /// Deletes the Board. Its References stay in the Library.
    static func delete(_ board: Board, in context: ModelContext) {
        board.references = []
        context.delete(board)
    }
}
