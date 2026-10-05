#if os(macOS)
import AppKit
import SwiftUI

/// Trackpad and mouse input for the Map, which SwiftUI gestures don't cover:
/// two-finger scroll pans, pinch zooms around the pointer, ⌘-scroll (mouse wheel) zooms.
/// Events are only taken while the pointer is over the Map; everywhere else they pass through.
struct ScrollZoomMonitor: ViewModifier {
    let controller: CanvasController

    func body(content: Content) -> some View {
        content
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        guard controller.eventMonitor == nil else { return }
        let controller = self.controller
        controller.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
            let type = event.type
            let values = EventValues(event)
            // Local monitors run on the main thread.
            let handled = MainActor.assumeIsolated {
                Self.handle(type: type, event: values, controller: controller)
            }
            return handled ? nil : event
        }
    }

    private func remove() {
        if let monitor = controller.eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        controller.eventMonitor = nil
    }

    /// The parts of an NSEvent the Map needs, copied out so they can cross into the main actor.
    struct EventValues: Sendable {
        let scrollX: CGFloat
        let scrollY: CGFloat
        let precise: Bool
        let command: Bool
        let magnification: CGFloat

        init(_ event: NSEvent) {
            let isScroll = event.type == .scrollWheel
            scrollX = isScroll ? event.scrollingDeltaX : 0
            scrollY = isScroll ? event.scrollingDeltaY : 0
            precise = isScroll && event.hasPreciseScrollingDeltas
            command = event.modifierFlags.contains(.command)
            magnification = event.type == .magnify ? event.magnification : 0
        }
    }

    @MainActor
    private static func handle(type: NSEvent.EventType, event: EventValues, controller: CanvasController) -> Bool {
        // Over an open detail, scrolling scrolls the detail.
        guard !controller.isShowingDetail, let pointer = controller.pointer else { return false }
        switch type {
        case .magnify:
            controller.zoom(by: 1 + event.magnification, at: pointer)
            return true
        case .scrollWheel:
            // A mouse wheel reports lines, a trackpad points.
            let scale: CGFloat = event.precise ? 1 : 10
            if event.command {
                controller.zoom(by: exp(event.scrollY * scale * 0.005), at: pointer)
            } else {
                controller.pan(by: CGSize(width: event.scrollX * scale, height: event.scrollY * scale))
            }
            return true
        default:
            return false
        }
    }
}
#endif
