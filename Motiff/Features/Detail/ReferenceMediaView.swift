import AVKit
import ImageIO
import SwiftUI

/// A Reference's media, shown whole. Images are decoded large; GIFs and videos loop, muted.
/// With Reduce Motion on, GIFs show their first frame.
struct ReferenceMediaView: View {
    let reference: Reference

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch reference.mediaType {
        case .image:
            still
        case .gif:
            if reduceMotion { still } else { AnimatedImage(url: reference.mediaURL) }
        case .video:
            LoopingVideo(url: reference.mediaURL)
        }
    }

    private var still: some View {
        ThumbnailImage(url: reference.mediaURL, pointSize: 2048, contentMode: .fit)
    }
}

/// Plays an animated image file (GIF, APNG) frame by frame with ImageIO.
private struct AnimatedImage: View {
    let url: URL

    @State private var player = AnimatedImagePlayer()

    var body: some View {
        Group {
            if let frame = player.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .onAppear { player.start(url: url) }
        .onDisappear { player.stop() }
    }
}

@MainActor
@Observable
final class AnimatedImagePlayer {
    var frame: CGImage?
    private var generation = 0

    func start(url: URL) {
        generation += 1
        let current = generation
        // ImageIO calls the block on the main queue, once per frame, until `stop` is set.
        _ = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, image, stop in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else {
                    stop.pointee = true
                    return
                }
                self.frame = image
            }
        }
    }

    func stop() {
        generation += 1
    }
}

/// A muted video that loops, with the system playback controls.
private struct LoopingVideo: View {
    let url: URL

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let player = AVQueuePlayer()
                player.isMuted = true
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                looper = nil
                player = nil
            }
    }
}
