import SwiftData
import XCTest

final class BoardTests: XCTestCase {
    @MainActor
    func testAddingTwiceKeepsOneAndRemovingKeepsTheReference() throws {
        let store = try TestStore()
        let board = Board.make(name: "Mood", in: store.context)
        let first = store.makeReference()
        let second = store.makeReference()

        board.add([first, second])
        board.add([first])
        try store.context.save()
        XCTAssertEqual(board.references.count, 2)
        XCTAssertTrue(first.boards.contains { $0.id == board.id })

        board.remove(first)
        try store.context.save()
        XCTAssertEqual(board.references.map(\.id), [second.id])
        XCTAssertFalse(first.boards.contains { $0.id == board.id })
        XCTAssertEqual(try store.count(Reference.self), 2, "taking it off the Board keeps it in the Library")
    }

    @MainActor
    func testDeletingABoardKeepsItsReferences() throws {
        let store = try TestStore()
        let board = Board.make(name: "Light", in: store.context)
        let other = Board.make(name: "Color", in: store.context)
        let reference = store.makeReference()
        board.add([reference])
        other.add([reference])
        try store.context.save()

        Board.delete(board, in: store.context)
        try store.context.save()

        XCTAssertEqual(try store.count(Board.self), 1)
        XCTAssertEqual(try store.count(Reference.self), 1)
        XCTAssertEqual(reference.boards.map(\.id), [other.id], "it stays on its other Boards")
    }

    @MainActor
    func testAnUnnamedBoardHasADisplayName() throws {
        let store = try TestStore()
        XCTAssertEqual(Board.make(name: "  ", in: store.context).displayName, "Untitled board")
        XCTAssertEqual(Board.make(name: "Mood", in: store.context).displayName, "Mood")
    }

    @MainActor
    func testBoardsListNewestReferencesFirst() throws {
        let store = try TestStore()
        let board = Board.make(name: "Mood", in: store.context)
        let older = store.makeReference()
        older.createdAt = .now.addingTimeInterval(-60)
        let newer = store.makeReference()
        board.add([older, newer])
        XCTAssertEqual(board.sortedReferences.map(\.id), [newer.id, older.id])
    }
}
