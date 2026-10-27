import SwiftUI

struct CollapsedView: View {
    @ObservedObject var music: MusicService
    @ObservedObject var usage: CommandCodeUsageService
    let mode: IslandMode
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            leadingWing
            Spacer(minLength: notchWidth)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leadingWing: some View {
        if mode == .commandCode {
            usageWing
        } else {
            artwork
        }
    }

    private var usageWing: some View {
        ZStack {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(usage.snapshot == nil ? 0.28 : 0.82))
                .overlay(alignment: .bottomTrailing) {
                    if usage.snapshot?.isExceeded == true {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                            .offset(x: 1.5, y: 1.5)
                    }
                }
        }
        .frame(width: 20, height: 20)
        .frame(width: 28, alignment: .leading)
    }

    private var artwork: some View {
        ZStack {
            if music.hasTrack {
                ArtworkThumb(image: music.artwork, size: 20, corner: 5.5)
                    .overlay(alignment: .bottomTrailing) {
                        if music.isPlaying {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
                                .offset(x: 1.5, y: 1.5)
                        }
                    }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 28, alignment: .leading)
    }
}
