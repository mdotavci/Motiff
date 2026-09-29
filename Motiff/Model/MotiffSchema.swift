import SwiftData

/// Every model in the store, in one place, so the app and the tests open the same schema.
///
/// Changes so far are additive (new models, new optional or defaulted fields), which SwiftData
/// migrates on its own. Introduce a `VersionedSchema` with the first change that isn't.
enum MotiffSchema {
    static var models: [any PersistentModel.Type] {
        [
            Reference.self,
            Board.self,
            Canvas.self,
            CanvasNode.self,
            CanvasLink.self,
            CanvasCategory.self,
        ]
    }

    static var schema: Schema {
        Schema(models)
    }
}
