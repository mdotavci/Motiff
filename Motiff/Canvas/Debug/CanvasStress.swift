import CoreGraphics
import Foundation
import SwiftData

/// A big Canvas for checking speed: a root, 12 Ideas far apart, and cards around them up to
/// 500 nodes, every one placed in a free spot. Debug › Generate 500-Node Canvas makes one.
enum CanvasStress {
    static let title = "500 nodes"
    static let total = 500

    @MainActor
    @discardableResult
    static func make(in context: ModelContext, references: [Reference] = []) -> Canvas {
        let new = CanvasGraph.makeCanvas(title: title, rootTitle: title, in: context)
        var ideas: [CanvasNode] = []
        for index in 0..<12 {
            guard let idea = CanvasGraph.addChild(.idea, under: new.root, title: "Idea \(index + 1)", in: context) else { continue }
            let angle = CGFloat(index) / 12 * 2 * .pi
            idea.position = CGPoint(x: cos(angle) * 1600, y: sin(angle) * 1600)
            idea.category = new.categories[index % new.categories.count]
            ideas.append(idea)
        }
        var made = 1 + ideas.count
        var index = 0
        while made < total, !ideas.isEmpty {
            let idea = ideas[index % ideas.count]
            if index % 3 == 0 || references.isEmpty {
                CanvasGraph.addChild(.note, under: idea, body: "Note \(index + 1): what this one is about", in: context)
            } else {
                let node = CanvasGraph.addNode(
                    .reference, to: new.canvas, parent: idea, at: idea.position,
                    reference: references[index % references.count], in: context
                )
                node.position = CanvasGraph.freeSpot(for: node, around: idea)
            }
            made += 1
            index += 1
        }
        try? context.save()
        return new.canvas
    }
}
