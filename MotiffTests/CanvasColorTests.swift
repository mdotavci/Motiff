import CoreGraphics
import SwiftData
import XCTest

final class CanvasColorTests: XCTestCase {
    /// WCAG contrast of two "#RRGGBB" colors.
    private func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = Int(hex.dropFirst(), radix: 16) ?? 0
            func channel(_ shift: Int) -> Double {
                let c = Double((value >> shift) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testEveryPastelReadsInBothThemes() {
        XCTAssertEqual(CanvasCategory.swatches.count, 16)
        for swatch in CanvasCategory.swatches {
            let words = max(contrast("#141414", swatch.hex), contrast("#FFFFFF", swatch.hex))
            XCTAssertGreaterThanOrEqual(words, 4.5, "\(swatch.name): words on the fill")
            XCTAssertGreaterThanOrEqual(contrast(swatch.ink, "#F4F4F2"), 4.5, "\(swatch.name): ink on the light ground")
            XCTAssertGreaterThanOrEqual(contrast(swatch.onDark, "#141414"), 3, "\(swatch.name): line on the dark ground")
            XCTAssertFalse(CanvasCategory.isFocusRed(swatch.hex), "\(swatch.name) looks like focus red")
            XCTAssertFalse(CanvasCategory.isFocusRed(swatch.ink), "\(swatch.name)'s ink looks like focus red")
        }
        XCTAssertTrue(CanvasCategory.defaults.allSatisfy { CanvasCategory.swatch(for: $0.hex) != nil })
    }

    @MainActor
    func testFirstPaletteMovesToThePastelOne() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        new.categories[0].colorHex = "#C58A2C"
        new.categories[1].colorHex = "#123456"

        CanvasGraph.migrateToPastelPalette(new.canvas.categories)

        XCTAssertEqual(new.categories[0].colorHex, "#F6D77A", "amber became yellow")
        XCTAssertEqual(new.categories[1].colorHex, "#123456", "custom colors stay")
        XCTAssertEqual(Set(CanvasCategory.legacyColors.values).subtracting(CanvasCategory.swatches.map(\.hex)), [])
    }

    @MainActor
    func testNodesTakeTheirOwnColorOverTheCategoryAndGoBack() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let note = try XCTUnwrap(CanvasGraph.addChild(.note, under: new.root, body: "Soft light", in: store.context))
        let text = CanvasGraph.addNode(.text, to: new.canvas, at: .zero, body: "Mood", in: store.context)
        CanvasGraph.setCategory([note], to: new.categories[1])

        XCTAssertEqual(note.effectiveColorHex, new.categories[1].colorHex)
        XCTAssertTrue(CanvasGraph.setColor("#bdebd8", of: [note, text]))
        XCTAssertEqual(note.effectiveColorHex, "#BDEBD8")
        XCTAssertEqual(text.textColorHex, "#BDEBD8", "Text takes it as the color of its words")
        XCTAssertNil(text.colorHex)

        XCTAssertFalse(CanvasGraph.setColor("#E2231A", of: [note]), "focus red is refused")
        XCTAssertEqual(note.colorHex, "#BDEBD8")

        XCTAssertTrue(CanvasGraph.setColor(nil, of: [note]))
        XCTAssertEqual(note.effectiveColorHex, new.categories[1].colorHex, "back to the category")
    }

    @MainActor
    func testLinesCarryTheirColorAndArrowIntoTheSnapshot() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let idea = try XCTUnwrap(CanvasGraph.addChild(.idea, under: new.root, title: "Light", in: store.context))
        let note = try XCTUnwrap(CanvasGraph.addChild(.note, under: idea, body: "Hard", in: store.context))
        let link = try XCTUnwrap(CanvasGraph.link(note, to: new.root, in: store.context))

        CanvasGraph.setLineColor("#9CC4F2", child: note, link: nil)
        CanvasGraph.setArrow(true, child: note, link: nil)
        CanvasGraph.setLineColor("#2A7638", child: nil, link: link)
        CanvasGraph.setArrow(false, child: nil, link: link)
        try store.context.save()

        let snapshot = CanvasSnapshot(canvas: new.canvas)
        let belongs = try XCTUnwrap(snapshot.edges.first { $0.type == .belongsTo && $0.to == note.id })
        XCTAssertEqual(belongs.colorHex, "#9CC4F2")
        XCTAssertTrue(belongs.hasArrow)
        let relates = try XCTUnwrap(snapshot.edges.first { $0.type == .relatesTo })
        XCTAssertEqual(relates.colorHex, "#2A7638")
        XCTAssertFalse(relates.hasArrow)
        let plain = try XCTUnwrap(snapshot.edges.first { $0.type == .belongsTo && $0.to == idea.id })
        XCTAssertNil(plain.colorHex)
        XCTAssertFalse(plain.hasArrow, "belongs-to lines start without an arrow")
    }
}
