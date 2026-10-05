import SwiftData
import XCTest

/// Step 19: a prompt's model, settings, your own fields and other versions.
final class PromptSettingsTests: XCTestCase {
    func testSettingsRoundTripKeepingYourFieldsInOrder() {
        var settings = PromptSettings()
        settings.known[.aspect] = "4:5"
        settings.known[.negative] = "text, watermark"
        settings.custom = [
            PromptSettings.Field(key: "Lens", value: "85mm"),
            PromptSettings.Field(key: "Client", value: "Mira"),
        ]

        let back = PromptSettings(settings.dictionary)
        XCTAssertEqual(back.known[.aspect], "4:5")
        XCTAssertEqual(back.known[.negative], "text, watermark")
        XCTAssertEqual(back.custom.map(\.key), ["Lens", "Client"], "the order you added them in")
        XCTAssertEqual(back, settings)
    }

    func testSettingsFromBeforeThereWasAnOrderStillShow() {
        let old = ["stylize": "250", "chaos": "10", "Seed": "42"]
        let settings = PromptSettings(old)
        XCTAssertEqual(settings.known[.seed], "42")
        XCTAssertEqual(settings.custom.map(\.key), ["chaos", "stylize"])
    }

    func testEmptyValuesAndNamelessFieldsAreNotKept() {
        var settings = PromptSettings()
        settings.known[.seed] = ""
        settings.custom = [PromptSettings.Field(key: "  ", value: "x")]
        XCTAssertTrue(settings.dictionary.isEmpty)
    }

    func testNewFieldNamesDontClash() {
        var settings = PromptSettings()
        XCTAssertEqual(settings.newFieldName(), "Field")
        settings.custom = [PromptSettings.Field(key: "Field", value: ""), PromptSettings.Field(key: "Field 2", value: "")]
        XCTAssertEqual(settings.newFieldName(), "Field 3")
    }

    func testMidjourneyGetsItsParametersAfterThePrompt() {
        var settings = PromptSettings()
        settings.known[.aspect] = "4:5"
        settings.known[.seed] = "12"
        settings.known[.negative] = "text"
        settings.known[.parameters] = "--stylize 250"
        XCTAssertEqual(
            settings.formatted("matte ceramic mug", model: "Midjourney v7"),
            "matte ceramic mug --ar 4:5 --seed 12 --no text --stylize 250"
        )
        XCTAssertEqual(
            settings.formatted("mug --ar 1:1", model: "Midjourney"),
            "mug --ar 1:1 --seed 12 --no text --stylize 250",
            "an aspect ratio already in the prompt wins"
        )
    }

    func testStableDiffusionGetsTheNegativePromptOnItsOwnLine() {
        var settings = PromptSettings()
        settings.known[.negative] = "blurry"
        XCTAssertEqual(settings.formatted("a mug", model: "Stable Diffusion XL"), "a mug\nNegative prompt: blurry")
        XCTAssertEqual(settings.formatted("a mug", model: "Claude"), "a mug", "a text model gets the text alone")
        XCTAssertEqual(settings.formatted("a mug", model: nil), "a mug")
    }

    @MainActor
    func testAReferenceCopiesItsPromptWithItsSettings() throws {
        let store = try TestStore()
        let reference = store.makeReference()
        reference.promptRaw = "soft window light"
        reference.model = "Midjourney"
        var settings = reference.promptSettings
        settings.known[.aspect] = "3:2"
        reference.promptSettings = settings

        XCTAssertEqual(reference.promptToCopy, "soft window light --ar 3:2")
        XCTAssertEqual(reference.copyablePrompt, "soft window light", "the card still shows the plain prompt")
    }

    @MainActor
    func testWritingAPromptOnTheBoardChangesItsReference() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let reference = store.makeReference()
        let card = CanvasGraph.addNode(.prompt, to: new.canvas, at: .zero, reference: reference, in: store.context)

        CanvasGraph.setPrompt("hard flash, deep shadow", of: card)
        XCTAssertEqual(reference.promptRaw, "hard flash, deep shadow")
        XCTAssertEqual(card.displayTitle, reference.caption)
    }
}
