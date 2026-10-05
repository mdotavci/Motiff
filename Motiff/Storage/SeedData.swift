import CoreGraphics
import Foundation
import SwiftData

/// Twelve References so the app is never opened to an empty grid, created once, the first
/// time the SwiftData store has none. All media is generated placeholder art — no image
/// assets are shipped. Then one example board built from them (`SeedData+Canvas.swift`). The two
/// old-style Boards it makes are turned into boards by `migrateBoardsIfNeeded`, as a library
/// from before boards were merged would be.
enum SeedData {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        seedReferencesIfNeeded(context: context)
        seedCanvasIfNeeded(context: context)
        migratePaletteIfNeeded(context: context)
        migrateBoardsIfNeeded(context: context)
    }

    @MainActor
    private static func seedReferencesIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Reference>())) ?? 0
        guard existing == 0 else { return }

        let references = specs.map(makeReference)
        for reference in references {
            context.insert(reference)
        }

        // A couple of Remixes, to seed Lineage.
        references[8].parent = references[0]
        references[11].parent = references[5]

        let productPhotography = Board(name: "Product photography")
        productPhotography.references = [references[0], references[5], references[11]]
        context.insert(productPhotography)

        let uiResearch = Board(name: "UI research")
        uiResearch.references = [references[3], references[4], references[6]]
        context.insert(uiResearch)

        try? context.save()
    }

    private struct Spec {
        var origin: Origin
        var background: (CGFloat, CGFloat, CGFloat)
        var accent: (CGFloat, CGFloat, CGFloat)
        var style: PlaceholderImageGenerator.Style
        var recipe: [RecipePart] = []
        var why: [WhyChip]
        var whyNote: String?
        var model: String?
        var sourcePlatform: String?
        var sourceURL: String?
        var creator: String?
        var recipeIsDescribed: Bool = false
    }

    private static let specs: [Spec] = [
        // 0 — Generated, matches the Recipe card example in the brief.
        Spec(
            origin: .generated,
            background: (0.95, 0.95, 0.94), accent: (0.09, 0.09, 0.09), style: .halves,
            recipe: [
                RecipePart(kind: .subject, text: "matte ceramic bottle, no label"),
                RecipePart(kind: .composition, text: "centered, low angle, lots of negative space"),
                RecipePart(kind: .light, text: "harsh direct flash, hard shadow"),
                RecipePart(kind: .material, text: "glazed ceramic, slight imperfection"),
                RecipePart(kind: .color, text: "off-white on saturated red"),
                RecipePart(kind: .texture, text: "fine film grain"),
                RecipePart(kind: .style, text: "editorial product photography"),
                RecipePart(kind: .mood, text: "raw, confident"),
                RecipePart(kind: .params, text: "--ar 4:5 --style raw"),
            ],
            why: [.light], model: "Midjourney v7"
        ),
        // 1 — Found, a UI screenshot.
        Spec(
            origin: .found,
            background: (0.98, 0.98, 0.97), accent: (0.85, 0.15, 0.1), style: .bands,
            why: [.layout], sourcePlatform: "Pinterest",
            sourceURL: "https://pin.it/brutalist-poster-01", creator: "studio.grau",
            recipeIsDescribed: true
        ),
        // 2 — Mine, a phone photo of a sketch.
        Spec(
            origin: .mine,
            background: (0.93, 0.92, 0.9), accent: (0.2, 0.2, 0.22), style: .corner,
            why: [.idea], whyNote: "the diagonal crop"
        ),
        // 3 — Generated, soft UI onboarding.
        Spec(
            origin: .generated,
            background: (0.9, 0.93, 0.97), accent: (0.98, 0.98, 1.0), style: .circle,
            recipe: [
                RecipePart(kind: .subject, text: "onboarding screen, three cards, soft shadows"),
                RecipePart(kind: .color, text: "pale blue and white"),
                RecipePart(kind: .style, text: "soft UI, rounded corners"),
                RecipePart(kind: .params, text: "--ar 9:16"),
            ],
            why: [.color], model: "Flux"
        ),
        // 4 — Found, pharmacy app UI.
        Spec(
            origin: .found,
            background: (1.0, 1.0, 1.0), accent: (0.05, 0.45, 0.35), style: .halves,
            why: [.layout], whyNote: "add-to-cart under the price",
            sourcePlatform: "Instagram", sourceURL: "https://instagram.com/p/pharmacy-ux",
            recipeIsDescribed: true
        ),
        // 5 — Generated, editorial fashion.
        Spec(
            origin: .generated,
            background: (0.08, 0.08, 0.08), accent: (0.8, 0.78, 0.7), style: .corner,
            recipe: [
                RecipePart(kind: .subject, text: "model in structured coat, studio backdrop"),
                RecipePart(kind: .light, text: "single hard key light, deep shadow"),
                RecipePart(kind: .mood, text: "cold, severe"),
                RecipePart(kind: .params, text: "--ar 4:5"),
            ],
            why: [.mood], model: "GPT Image"
        ),
        // 6 — Found, type specimen poster.
        Spec(
            origin: .found,
            background: (0.97, 0.96, 0.94), accent: (0.1, 0.1, 0.1), style: .bands,
            why: [.type], sourcePlatform: "Behance",
            sourceURL: "https://behance.net/gallery/type-specimen-02", creator: "atelier.set",
            recipeIsDescribed: true
        ),
        // 7 — Mine, packaging photo.
        Spec(
            origin: .mine,
            background: (0.94, 0.9, 0.86), accent: (0.55, 0.4, 0.3), style: .circle,
            why: [.texture]
        ),
        // 8 — Remix, child of 0 (parent set after creation). Same subject, changed light.
        Spec(
            origin: .remix,
            background: (0.95, 0.95, 0.94), accent: (0.85, 0.6, 0.1), style: .halves,
            recipe: [
                RecipePart(kind: .subject, text: "matte ceramic bottle, no label"),
                RecipePart(kind: .composition, text: "centered, low angle, lots of negative space"),
                RecipePart(kind: .light, text: "soft window light, long diffuse shadow"),
                RecipePart(kind: .material, text: "glazed ceramic, slight imperfection"),
                RecipePart(kind: .color, text: "off-white on saturated red"),
                RecipePart(kind: .texture, text: "fine film grain"),
                RecipePart(kind: .style, text: "editorial product photography"),
                RecipePart(kind: .mood, text: "calm, warm"),
                RecipePart(kind: .params, text: "--ar 4:5 --style raw"),
            ],
            why: [.light], model: "Midjourney v7"
        ),
        // 9 — Found, texture close-up.
        Spec(
            origin: .found,
            background: (0.75, 0.72, 0.68), accent: (0.4, 0.38, 0.35), style: .bands,
            why: [.texture], sourcePlatform: "Behance",
            sourceURL: "https://behance.net/gallery/concrete-texture-14", creator: "material.log",
            recipeIsDescribed: true
        ),
        // 10 — Generated, packaging concept.
        Spec(
            origin: .generated,
            background: (0.92, 0.95, 0.9), accent: (0.15, 0.3, 0.15), style: .corner,
            recipe: [
                RecipePart(kind: .subject, text: "kraft paper box, minimal die-cut window"),
                RecipePart(kind: .color, text: "kraft brown, single green foil stamp"),
                RecipePart(kind: .style, text: "product render, studio lighting"),
                RecipePart(kind: .params, text: "--ar 1:1"),
            ],
            why: [.layout], model: "Krea"
        ),
        // 11 — Remix, child of 5 (parent set after creation). Same scene, warmer mood.
        Spec(
            origin: .remix,
            background: (0.2, 0.16, 0.12), accent: (0.85, 0.65, 0.4), style: .corner,
            recipe: [
                RecipePart(kind: .subject, text: "model in structured coat, studio backdrop"),
                RecipePart(kind: .light, text: "warm rim light, soft fill"),
                RecipePart(kind: .mood, text: "warm, inviting"),
                RecipePart(kind: .params, text: "--ar 4:5"),
            ],
            why: [.mood], model: "GPT Image"
        ),
    ]

    @MainActor
    private static func makeReference(from spec: Spec) -> Reference {
        let size = CGSize(width: 800, height: 1000)
        let pngSpec = PlaceholderImageGenerator.Spec(
            background: CGColor(red: spec.background.0, green: spec.background.1, blue: spec.background.2, alpha: 1),
            accent: CGColor(red: spec.accent.0, green: spec.accent.1, blue: spec.accent.2, alpha: 1),
            style: spec.style
        )
        let data = PlaceholderImageGenerator.pngData(size: size, spec: pngSpec) ?? Data()
        let filename = (try? MediaStore.store(data, fileExtension: "png")) ?? "placeholder.png"

        let reference = Reference(
            mediaFilename: filename,
            mediaType: .image,
            width: Int(size.width),
            height: Int(size.height),
            origin: spec.origin
        )
        reference.recipe = spec.recipe
        reference.recipeIsDescribed = spec.recipeIsDescribed
        reference.why = spec.why
        reference.whyNote = spec.whyNote
        reference.model = spec.model
        reference.sourcePlatform = spec.sourcePlatform
        reference.sourceURL = spec.sourceURL
        reference.creator = spec.creator
        reference.promptRaw = spec.recipe.isEmpty ? nil : reference.assembledPrompt
        reference.purpose = spec.recipe.isEmpty ? nil : .image
        reference.aiState = .done
        return reference
    }
}
