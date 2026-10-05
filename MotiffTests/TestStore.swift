import SwiftData
import XCTest

/// An in-memory store with the app's full schema, fresh for each test.
@MainActor
struct TestStore {
    let container: ModelContainer

    init() throws {
        let configuration = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: MotiffSchema.schema, configurations: configuration)
    }

    var context: ModelContext { container.mainContext }

    func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }

    /// A Reference with a made-up media filename; no file is written.
    func makeReference(origin: Origin = .found) -> Reference {
        let reference = Reference(
            mediaFilename: "test-\(UUID().uuidString).png",
            mediaType: .image,
            width: 800,
            height: 1000,
            origin: origin
        )
        context.insert(reference)
        return reference
    }
}
