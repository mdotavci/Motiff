import SwiftData
import SwiftUI

/// Every Canvas as a big dot, and each Reference that's on more than one of them as a small dot
/// joined to those Canvases: where your boards of ideas overlap. Double-click a Canvas to open it.
struct CanvasGraphOverview: View {
    let open: (Canvas) -> Void

    @Query(sort: \Canvas.createdAt) private var canvases: [Canvas]
    @State private var selection: UUID?

    var body: some View {
        let model = Self.model(of: canvases)
        Group {
            if canvases.isEmpty {
                EmptyState(title: "Board Graph", message: "Make a board (⌘N) to see it here.")
            } else {
                ForceGraphView(
                    model: model,
                    selection: selection.map { [$0] } ?? [],
                    highlighted: selection.map { Self.neighbors(of: $0, in: model) }
                ) { id, _ in
                    selection = id
                } onOpen: { id in
                    if let canvas = canvases.first(where: { $0.id == id }) { open(canvas) }
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Boards and the References they share").motiffLabel()
                        if model.edges.isEmpty {
                            Text("No Reference is on more than one board yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Double-click a board to open it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(Theme.gutter)
                    .allowsHitTesting(false)
                }
            }
        }
        .navigationTitle("Board Graph")
    }

    /// Canvases around a circle; each shared Reference starts between the Canvases it's on.
    @MainActor
    static func model(of canvases: [Canvas]) -> ForceGraphModel {
        var nodes: [ForceGraphModel.Node] = []
        var edges: [ForceGraphModel.Edge] = []
        var seeds: [UUID: CGPoint] = [:]
        let ring = CGFloat(max(canvases.count, 3)) * 60
        for (index, canvas) in canvases.enumerated() {
            let angle = CGFloat(index) / CGFloat(max(canvases.count, 1)) * 2 * .pi
            let seed = CGPoint(x: cos(angle) * ring, y: sin(angle) * ring)
            seeds[canvas.id] = seed
            nodes.append(ForceGraphModel.Node(
                id: canvas.id, label: canvas.displayTitle, colorHex: nil, radius: 11, seed: seed, showsLabel: true
            ))
        }

        // Each Reference with the Canvases it's on, in a stable order.
        var onCanvases: [UUID: (reference: Reference, canvases: [UUID])] = [:]
        for canvas in canvases {
            for node in canvas.nodes where !node.isDeleted {
                guard let reference = node.reference else { continue }
                var entry = onCanvases[reference.id] ?? (reference, [])
                if !entry.canvases.contains(canvas.id) { entry.canvases.append(canvas.id) }
                onCanvases[reference.id] = entry
            }
        }
        let shared = onCanvases.values
            .filter { $0.canvases.count > 1 }
            .sorted { $0.reference.createdAt < $1.reference.createdAt }
        for (index, entry) in shared.enumerated() {
            let points = entry.canvases.compactMap { seeds[$0] }
            let middle = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(points.count) + CGFloat(index % 5) * 7,
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count) + CGFloat(index % 3) * 7
            )
            nodes.append(ForceGraphModel.Node(
                id: entry.reference.id, label: entry.reference.caption, colorHex: nil, radius: 4, seed: middle, showsLabel: false
            ))
            for canvasID in entry.canvases {
                edges.append(ForceGraphModel.Edge(from: entry.reference.id, to: canvasID, dashed: false))
            }
        }
        return ForceGraphModel(nodes: nodes, edges: edges)
    }

    static func neighbors(of id: UUID, in model: ForceGraphModel) -> Set<UUID> {
        var result: Set<UUID> = [id]
        for edge in model.edges {
            if edge.from == id { result.insert(edge.to) }
            if edge.to == id { result.insert(edge.from) }
        }
        return result
    }
}
