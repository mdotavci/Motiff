import CoreGraphics
import Foundation
import SwiftData

/// The second example board, "Moodboard example": the same seed pictures laid out freely, with a
/// title, a sticky, two shapes, a prompt and a free arrow, to show what a board can hold.
extension SeedData {
    /// Set once the moodboard example has been made, so deleting it doesn't bring it back.
    static let moodboardSeededKey = "seed.moodboard"

    /// Makes the moodboard example once, from the twelve oldest References (the seed ones).
    @MainActor
    static func seedMoodboardIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: moodboardSeededKey) else { return }
        var oldest = FetchDescriptor<Reference>(sortBy: [SortDescriptor(\.createdAt)])
        oldest.fetchLimit = 12
        guard let references = try? context.fetch(oldest), references.count == 12 else { return }
        context.undoManager?.disableUndoRegistration()
        makeMoodboardExample(from: references, in: context)
        context.undoManager?.enableUndoRegistration()
        try? context.save()
        defaults.set(true, forKey: moodboardSeededKey)
    }

    /// A title, four pictures across the top, then a sticky, a rectangle, a star and an image
    /// prompt, the star pointing at the prompt. Everything loose: no belongs-to lines.
    @MainActor
    @discardableResult
    static func makeMoodboardExample(from references: [Reference], in context: ModelContext) -> Canvas {
        precondition(references.count >= 12, "Needs the twelve seed References")
        let new = CanvasGraph.makeCanvas(title: "Moodboard example", rootTitle: "Spring campaign", in: context)
        let canvas = new.canvas

        let title = CanvasGraph.addNode(.text, to: canvas, at: CGPoint(x: 0, y: -400), body: "Light, air and soft shadows", in: context)
        title.textSize = .large

        for (reference, x) in zip([references[0], references[5], references[8], references[2]], [-540.0, -330.0, 330.0, 540.0]) {
            CanvasGraph.addNode(.reference, to: canvas, at: CGPoint(x: x, y: -60), reference: reference, in: context)
        }

        CanvasGraph.addSticky(to: canvas, at: CGPoint(x: -440, y: 300), text: "Warm window light. Soft shadows. Lots of air around the product.", in: context)
        CanvasGraph.addShape(.rectangle, to: canvas, at: CGPoint(x: -160, y: 300), label: "Shot list", colorHex: "#BFE3F5", in: context)
        CanvasGraph.addShape(.star, to: canvas, at: CGPoint(x: 90, y: 300), label: "Hero shot", colorHex: "#F3B2C6", in: context)
        CanvasGraph.addNode(.prompt, to: canvas, at: CGPoint(x: 440, y: 300), reference: references[11], in: context)
        CanvasGraph.addLine(from: CGPoint(x: 180, y: 300), to: CGPoint(x: 330, y: 300), on: canvas, in: context)
        return canvas
    }
}
