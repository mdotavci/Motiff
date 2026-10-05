import CoreGraphics
import Foundation
import SwiftData

/// The example Canvas: "Product photography look", built from the seed References.
extension SeedData {
    /// Set once the example Canvas has been made, so deleting it doesn't bring it back.
    static let canvasSeededKey = "seed.canvas"
    /// Set once Canvases made with the first palette have moved to the pastel one.
    static let pastelPaletteKey = "palette.v2"

    /// Recolors categories that still use the first palette's colors, once.
    @MainActor
    static func migratePaletteIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: pastelPaletteKey) else { return }
        let categories = (try? context.fetch(FetchDescriptor<CanvasCategory>())) ?? []
        // Not something to undo.
        context.undoManager?.disableUndoRegistration()
        CanvasGraph.migrateToPastelPalette(categories)
        context.undoManager?.enableUndoRegistration()
        try? context.save()
        defaults.set(true, forKey: pastelPaletteKey)
    }

    /// Makes the example Canvas the first time the app runs with Canvases, including on a
    /// library seeded before Canvases existed. Uses the twelve oldest References, which are
    /// the seed ones in seed order; does nothing if there are fewer.
    @MainActor
    static func seedCanvasIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: canvasSeededKey) else { return }

        let canvases = (try? context.fetchCount(FetchDescriptor<Canvas>())) ?? 0
        if canvases == 0 {
            var oldest = FetchDescriptor<Reference>(sortBy: [SortDescriptor(\.createdAt)])
            oldest.fetchLimit = 12
            guard let references = try? context.fetch(oldest), references.count == 12 else { return }
            makeExampleCanvas(from: references, in: context)
            try? context.save()
        }
        defaults.set(true, forKey: canvasSeededKey)
    }

    /// Root Idea, two sub-ideas, six References, an Image and a Text prompt, two notes,
    /// one cross-link and four categories. `references` are the twelve seed References in order.
    @MainActor
    @discardableResult
    static func makeExampleCanvas(from references: [Reference], in context: ModelContext) -> Canvas {
        precondition(references.count >= 12, "Needs the twelve seed References")

        // Libraries seeded before prompts had a purpose.
        for reference in references where reference.purpose == nil && !reference.recipe.isEmpty {
            reference.purpose = .image
        }

        let new = CanvasGraph.makeCanvas(
            title: "Product photography look",
            rootTitle: "Product photography look",
            categories: [
                .init(name: "Light", hex: "#F6D77A"),
                .init(name: "Composition", hex: "#9CC4F2"),
                .init(name: "Reference", hex: "#8FD6CF"),
                .init(name: "To try", hex: "#F7B98A"),
            ],
            in: context
        )
        let canvas = new.canvas
        let light = new.categories[0]
        let composition = new.categories[1]
        let found = new.categories[2]
        let toTry = new.categories[3]

        func idea(_ title: String, _ category: CanvasCategory, at point: CGPoint) -> CanvasNode {
            CanvasGraph.addNode(.idea, to: canvas, parent: new.root, at: point, title: title, category: category, in: context)
        }
        func card(
            _ kind: NodeKind,
            on parent: CanvasNode,
            at point: CGPoint,
            reference: Reference? = nil,
            body: String? = nil,
            category: CanvasCategory? = nil
        ) {
            CanvasGraph.addNode(kind, to: canvas, parent: parent, at: point, body: body, reference: reference, category: category, in: context)
        }

        let lightIdea = idea("Light", light, at: CGPoint(x: -357, y: -408))
        let compositionIdea = idea("Composition", composition, at: CGPoint(x: 357, y: -408))

        card(.reference, on: lightIdea, at: CGPoint(x: -357, y: -745), reference: references[0])
        card(.reference, on: lightIdea, at: CGPoint(x: -615, y: -660), reference: references[8])
        card(.reference, on: lightIdea, at: CGPoint(x: -663, y: -306), reference: references[5], category: found)
        card(.prompt, on: lightIdea, at: CGPoint(x: -524, y: 0), reference: references[11], category: toTry)
        card(.note, on: lightIdea, at: CGPoint(x: -88, y: -680), body: "Hard light reads confident; soft light reads calm.")

        card(.reference, on: compositionIdea, at: CGPoint(x: 357, y: -745), reference: references[10])
        card(.reference, on: compositionIdea, at: CGPoint(x: 622, y: -660), reference: references[2], category: found)
        card(.reference, on: compositionIdea, at: CGPoint(x: 646, y: -289), reference: references[7])
        card(.prompt, on: compositionIdea, at: CGPoint(x: 612, y: 85), reference: makeTextPrompt(in: context), category: toTry)
        card(.note, on: compositionIdea, at: CGPoint(x: 340, y: -102), body: "Keep the product small, lots of negative space.")

        CanvasGraph.link(lightIdea, to: compositionIdea, label: "shadows shape the frame", in: context)
        return canvas
    }

    /// A Text prompt with no image: it shows a typographic cover.
    @MainActor
    private static func makeTextPrompt(in context: ModelContext) -> Reference {
        let prompt = Reference(mediaFilename: "", mediaType: .image, width: 0, height: 0, origin: .mine)
        context.insert(prompt)
        prompt.promptRaw = "Write a three-line shot brief for a product photo: subject, light, mood. Keep each line under eight words."
        prompt.purpose = .text
        prompt.aiState = .done
        return prompt
    }
}
