import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class CaptureTests: XCTestCase {
    func testPurposeGuesses() {
        XCTAssertEqual(PromptPurposeGuess.guess("matte ceramic mug on linen --ar 4:5 --v 7"), .image)
        XCTAssertEqual(PromptPurposeGuess.guess("Cinematic portrait of a chef, 85mm, soft lighting"), .image)
        XCTAssertEqual(PromptPurposeGuess.guess("Refactor this SwiftUI view to use @Observable and add a unit test"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("Fix this:\n```\nlet x = 1\n```"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("if (x) {\n  run();\n}"), .code)
        XCTAssertEqual(PromptPurposeGuess.guess("Rewrite this paragraph so it's half as long and warmer."), .text)
        XCTAssertEqual(
            PromptPurposeGuess.guess("Write a three-line shot brief for a product photo: subject, light, mood."),
            .text
        )
    }

    func testTIFFFromTheClipboardIsKeptAsPNG() throws {
        let tiff = try XCTUnwrap(Self.image(as: .tiff))
        let stored = ImageConversion.storable(tiff, type: .tiff)
        XCTAssertEqual(stored.type, .png)
        XCTAssertEqual(Array(stored.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")

        let jpeg = Data([0xFF, 0xD8, 0xFF])
        XCTAssertEqual(ImageConversion.storable(jpeg, type: .jpeg).type, .jpeg, "other types are kept as they are")
    }

    @MainActor
    func testOnlyThingsThatHoldThingsTakePastes() throws {
        let store = try TestStore()
        let new = CanvasGraph.makeCanvas(title: "", in: store.context)
        let prompt = CanvasGraph.addNode(.prompt, to: new.canvas, at: .zero, reference: store.makeReference(), in: store.context)
        let sticky = CanvasGraph.addSticky(to: new.canvas, at: .zero, in: store.context)
        let star = CanvasGraph.addShape(.star, to: new.canvas, at: .zero, in: store.context)
        let arrow = CanvasGraph.addLine(from: .zero, to: CGPoint(x: 50, y: 0), on: new.canvas, in: store.context)

        XCTAssertTrue(CanvasGraph.canHold(prompt))
        XCTAssertTrue(CanvasGraph.canHold(sticky))
        XCTAssertTrue(CanvasGraph.canHold(new.root))
        XCTAssertFalse(CanvasGraph.canHold(star))
        XCTAssertFalse(CanvasGraph.canHold(arrow))
    }

    /// A 2×2 image encoded as `type`.
    private static func image(as type: UTType) -> Data? {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let image = context?.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
