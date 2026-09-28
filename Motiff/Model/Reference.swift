import Foundation
import SwiftData

/// The only object in Motiff. Always visual first: a prompt never exists without a Reference,
/// and a Reference never exists without media.
@Model
final class Reference {
    var id: UUID = UUID()
    var createdAt: Date = Date.now

    // MARK: Media (required)

    var mediaFilename: String = ""
    var mediaTypeRaw: String = MediaType.image.rawValue
    var width: Int = 0
    var height: Int = 0

    // MARK: Origin

    var originRaw: String = Origin.found.rawValue

    // MARK: Recipe

    /// The real prompt for Generated; nil until "Describe as prompt" runs for Found.
    var promptRaw: String?
    var recipeData: Data?
    /// True when the recipe was written by AI from the image, not the original prompt.
    var recipeIsDescribed: Bool = false

    // MARK: Model + settings

    var model: String?
    var settingsData: Data?

    // MARK: Why

    var whyChipsRaw: [String] = []
    var whyNote: String?

    // MARK: Read (on-device + AI)

    var readTagsData: Data?
    var ocrText: String?
    var featurePrint: Data?

    // MARK: Source

    var sourceURL: String?
    var sourcePlatform: String?
    var creator: String?

    // MARK: Lineage

    @Relationship(deleteRule: .nullify) var parent: Reference?
    @Relationship(deleteRule: .cascade, inverse: \Reference.parent) var children: [Reference] = []

    // MARK: Boards

    /// Inverse declared on `Board.references`. A Reference can live on many Boards.
    var boards: [Board] = []

    // MARK: Status + AI state

    var statusRaw: String = ReferenceStatus.keep.rawValue
    var aiStateRaw: String = AIState.pending.rawValue
    /// First time the detail view was opened. Nil means it's still new (Inbox).
    var openedAt: Date?

    init(mediaFilename: String, mediaType: MediaType, width: Int, height: Int, origin: Origin) {
        self.mediaFilename = mediaFilename
        self.mediaTypeRaw = mediaType.rawValue
        self.width = width
        self.height = height
        self.originRaw = origin.rawValue
    }
}

// MARK: - Typed accessors

extension Reference {
    var mediaType: MediaType {
        get { MediaType(rawValue: mediaTypeRaw) ?? .image }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var origin: Origin {
        get { Origin(rawValue: originRaw) ?? .found }
        set { originRaw = newValue.rawValue }
    }

    var status: ReferenceStatus {
        get { ReferenceStatus(rawValue: statusRaw) ?? .keep }
        set { statusRaw = newValue.rawValue }
    }

    var aiState: AIState {
        get { AIState(rawValue: aiStateRaw) ?? .pending }
        set { aiStateRaw = newValue.rawValue }
    }

    var why: [WhyChip] {
        get { whyChipsRaw.compactMap(WhyChip.init(rawValue:)) }
        set { whyChipsRaw = newValue.map(\.rawValue) }
    }

    var recipe: [RecipePart] {
        get { recipeData.flatMap { try? JSONDecoder().decode([RecipePart].self, from: $0) } ?? [] }
        set { recipeData = try? JSONEncoder().encode(newValue) }
    }

    var settings: [String: String] {
        get { settingsData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set { settingsData = try? JSONEncoder().encode(newValue) }
    }

    var readTags: ReadTags? {
        get { readTagsData.flatMap { try? JSONDecoder().decode(ReadTags.self, from: $0) } }
        set { readTagsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The recipe's parts rebuilt into one prompt, in card order.
    var assembledPrompt: String {
        recipe.map(\.text).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The prompt to copy: the original one if there is one, else the recipe joined up.
    var copyablePrompt: String? {
        if let promptRaw, !promptRaw.isEmpty { return promptRaw }
        let assembled = assembledPrompt
        return assembled.isEmpty ? nil : assembled
    }

    /// Width divided by height, unclamped. For showing the media whole.
    var mediaAspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    /// Height divided by width, kept between 1:2 and 2:1 so no tile gets absurdly thin.
    var displayAspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return min(max(CGFloat(height) / CGFloat(width), 0.5), 2)
    }

    /// Every Remix made from this Reference, and Remixes of those, depth first.
    var descendants: [Reference] {
        children.flatMap { [$0] + $0.descendants }
    }

    var mediaURL: URL {
        MediaStore.url(for: mediaFilename)
    }
}

// MARK: - Deleting

extension Reference {
    /// Deletes this Reference, its Remixes (the lineage cascades), and all their media files.
    @MainActor
    static func delete(_ reference: Reference, in context: ModelContext) {
        let doomed = reference.descendants.reversed() + [reference]
        for item in doomed {
            MediaStore.delete(item.mediaFilename)
            context.delete(item)
        }
        try? context.save()
    }
}
