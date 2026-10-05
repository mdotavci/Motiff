#if DEBUG
import SwiftUI

/// Debug › Show Frame Rate: how many frames a second the main thread is drawing, averaged.
/// Watch it while panning and pinching a big Canvas; 60 on a 60 Hz display is the goal.
struct FrameRateMeter: View {
    @State private var meter = Meter()

    var body: some View {
        TimelineView(.animation) { timeline in
            Text(verbatim: "\(Int(meter.tick(timeline.date).rounded())) fps")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
        .allowsHitTesting(false)
    }

    /// Keeps a running average of the time between frames. A class, so ticking it while
    /// drawing doesn't itself cause another draw.
    final class Meter {
        private var last: Date?
        private var average: Double = 1.0 / 60

        func tick(_ date: Date) -> Double {
            if let last {
                let interval = min(max(date.timeIntervalSince(last), 1.0 / 240), 1)
                average = average * 0.9 + interval * 0.1
            }
            last = date
            return 1 / average
        }
    }
}
#endif
