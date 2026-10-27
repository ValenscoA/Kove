import SwiftUI

/// A miniature of the island, drawn with the same shape the app uses, so the
/// toggles below have something to point at.
struct IslandPreviewCard: View {

    let enabled: Set<IslandMode>
    let active: IslandMode?

    private let pillWidth: CGFloat = 218
    private let pillHeight: CGFloat = 30

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                // A sliver of "screen" so the pill reads as hanging from the top edge.
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)

                pill

                Spacer(minLength: 10)
                caption
                Spacer(minLength: 12)
            }
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: enabled)
    }

    private var pill: some View {
        HStack(spacing: 0) {
            leadingWing
            Spacer(minLength: 0)
            trailingDot
        }
        .padding(.horizontal, 6)
        .frame(width: pillWidth, height: pillHeight)
        .background(IslandShape(bottomCornerRadius: 11).fill(Color.black))
        .overlay(
            IslandShape(bottomCornerRadius: 11)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    lineWidth: 0.8
                )
        )
        .opacity(enabled.isEmpty ? 0 : 1)
        .overlay {
            if enabled.isEmpty {
                IslandShape(bottomCornerRadius: 11)
                    .stroke(
                        Color.white.opacity(0.16),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
            }
        }
    }

    @ViewBuilder
    private var leadingWing: some View {
        switch active {
        case .music:
            ArtworkThumb(image: nil, size: 20, corner: 5.5)
        case .commandCode:
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .frame(width: 20, height: 20)
        case nil:
            Color.clear.frame(width: 20, height: 20)
        }
    }

    private var trailingDot: some View {
        Circle()
            .fill(Color.white.opacity(active == nil ? 0 : 0.9))
            .frame(width: 5, height: 5)
            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1))
    }

    private var caption: some View {
        VStack(spacing: 3) {
            Text(headline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    private var headline: String {
        switch (enabled.isEmpty, active) {
        case (true, _):
            return "Island hidden"
        case (false, .music?):
            return "Music"
        case (false, .commandCode?):
            return "Command Code Usage"
        case (false, nil):
            return "Island hidden"
        }
    }

    private var detail: String {
        let count = enabled.count
        if count == 0 {
            return "Turn a source on to bring it back."
        }
        if count > 1 {
            return "Switch between sources from inside the island."
        }
        return "This is what appears on the notch."
    }
}
