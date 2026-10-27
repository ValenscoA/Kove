import SwiftUI

struct ExpandedView: View {
    @ObservedObject var media: MediaService
    @ObservedObject var usage: CommandCodeUsageService
    let mode: IslandMode
    /// Sources enabled in the menu bar; the switcher only offers these.
    let enabledSources: Set<IslandMode>
    let stripHeight: CGFloat
    let onSelectMode: (IslandMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            topStrip
                .frame(height: stripHeight)

            Group {
                switch mode {
                case .music:
                    MediaSection(media: media)
                case .commandCode:
                    CommandCodeUsageView(usage: usage)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: Self.contentRowHeight)
        }
    }

    static let contentRowHeight: CGFloat = 146

    private var topStrip: some View {
        HStack(spacing: 0) {
            Text(headerTitle)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)

            Spacer(minLength: 0)

            modeSwitcher
        }
        .padding(.horizontal, 18)
    }

    private var headerTitle: String {
        switch mode {
        case .music:
            media.hasTrack ? "NOW PLAYING" : "MUSIC"
        case .commandCode:
            "COMMAND CODE"
        }
    }

    @ViewBuilder
    private var modeSwitcher: some View {
        let offered = IslandMode.allCases.filter(enabledSources.contains)
        if offered.count > 1 {
            HStack(spacing: 2) {
                ForEach(offered, id: \.self) { source in
                    modeButton(source)
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .animation(.easeOut(duration: 0.12), value: mode)
        }
    }

    private func modeButton(_ target: IslandMode) -> some View {
        Button {
            onSelectMode(target)
        } label: {
            Image(systemName: target.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(mode == target ? 0.95 : 0.42))
                .frame(width: 22, height: 16)
                .background(Capsule().fill(Color.white.opacity(mode == target ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(target.helpText)
    }
}

struct MediaSection: View {
    @ObservedObject var media: MediaService

    var body: some View {
        if let track = media.track {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    ArtworkThumb(image: media.artwork, size: 96, corner: 14)
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .padding(.top, 2)

                        Text(track.album.isEmpty ? " " : track.album)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                            .padding(.top, 1)

                        TimelineView(.periodic(from: .now, by: media.isPlaying ? 0.5 : 5)) { _ in
                            ProgressRow(
                                progress: media.progress,
                                elapsed: media.position,
                                duration: track.duration,
                                onSeek: { media.seek(to: $0) }
                            )
                        }
                        .padding(.top, 11)
                    }
                }
                .frame(height: 96)

                HStack(spacing: 7) {
                    IconButton(systemName: "backward.fill", diameter: 24, iconSize: 11) {
                        media.previous()
                    }
                    IconButton(
                        systemName: media.isPlaying ? "pause.fill" : "play.fill",
                        diameter: 30,
                        iconSize: 13,
                        filled: true
                    ) {
                        media.togglePlayPause()
                    }
                    IconButton(systemName: "forward.fill", diameter: 24, iconSize: 11) {
                        media.next()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)
            }
        } else {
            EmptyMediaView(media: media)
        }
    }
}

struct EmptyMediaView: View {
    @ObservedObject var media: MediaService

    private var emptyMessage: String {
        if media.permissionDenied {
            let player = media.deniedPlayerName ?? "your player"
            return "Allow Kove to control \(player) in System Settings › Privacy & Security › Automation."
        }
        if media.isPlayerRunning {
            return "Start a track in Apple Music, Spotify, or any app that publishes a media session."
        }
        return "Open a player and start a track — Kove shows whatever is playing."
    }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkThumb(image: nil, size: 96, corner: 14)

            VStack(alignment: .leading, spacing: 5) {
                Text(media.permissionDenied ? "Access needed" : "Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                Text(emptyMessage)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

                Spacer(minLength: 6)

                Button {
                    media.openPlayer()
                } label: {
                    Text("Open Player")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 96, alignment: .top)
        }
    }
}
