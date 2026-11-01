import SwiftUI

/// Lyrics in the island: the current line centred and bright, two lines either side
/// dimmed. No artwork here, because lines need the full width to read.
struct LyricsView: View {
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                message("Loading lyrics…")
            case .instrumental:
                message("Instrumental")
            case .unavailable(let text):
                message(text)
            case .ready:
                if lyrics.isSynced {
                    synced
                } else {
                    untimed
                }
            }
        }
        .frame(height: ExpandedView.contentRowHeight, alignment: .center)
    }

    // MARK: Synced

    /// Five rows around the active line. Rows that fall outside the song keep their
    /// height so the block does not jump at the first and last line.
    private var synced: some View {
        VStack(spacing: 0) {
            // Before the first line is sung there is no active index. Treating that as
            // -1 keeps the upcoming lines dim instead of lighting up line 0 early.
            let active = lyrics.activeIndex ?? -1
            ForEach(-2...2, id: \.self) { offset in
                let index = active + offset
                let line = lyrics.lines.indices.contains(index) ? lyrics.lines[index].text : " "
                Text(line)
                    .font(.system(size: size(for: offset), weight: offset == 0 ? .semibold : .regular))
                    .foregroundStyle(Color.white.opacity(opacity(for: offset)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
            }

            // Slot always reserved, filled only when the timing came from a different edit.
            Text(lyrics.timingMayDrift ? "timing may be off for this version" : " ")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.tertiary)
                .frame(height: 14)
        }
        .animation(.easeOut(duration: 0.18), value: lyrics.activeIndex)
    }

    private let rowHeight: CGFloat = 25

    private func size(for offset: Int) -> CGFloat {
        switch abs(offset) {
        case 0: return 14
        case 1: return 12
        default: return 10.5
        }
    }

    private func opacity(for offset: Int) -> Double {
        switch abs(offset) {
        case 0: return 0.96
        case 1: return 0.45
        default: return 0.22
        }
    }

    // MARK: Untimed

    /// Some tracks only match on a plain text blob. Shown as text, with no highlight:
    /// a fake highlight would be worse than none.
    private var untimed: some View {
        VStack(spacing: 3) {
            ForEach(Array(lyrics.plainText.prefix(3).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Text("not timed")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 4)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
    }
}
