import SwiftUI

// MARK: - Artwork

struct ArtworkThumb: View {
    let image: NSImage?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }
}

// MARK: - Buttons

struct IconButton: View {
    let systemName: String
    var diameter: CGFloat = 26
    var iconSize: CGFloat = 12
    var filled = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(filled ? (hovering ? 0.28 : 0.16) : (hovering ? 0.13 : 0.0)))
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.85))
                    .offset(x: systemName == "play.fill" ? 0.6 : 0)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Progress

struct ProgressRow: View {
    let progress: Double
    let elapsed: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var draggedFraction: Double?
    @State private var hovering = false

    private var shown: Double { draggedFraction ?? progress }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.track)
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * shown, height: 3)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .offset(x: max(0, min(width - 7, width * shown - 3.5)))
                        .opacity(hovering || draggedFraction != nil ? 1 : 0)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draggedFraction = max(0, min(1, value.location.x / width))
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            draggedFraction = nil
                            onSeek(fraction * duration)
                        }
                )
                .onHover { hovering = $0 }
            }
            .frame(height: 9)

            HStack(spacing: 0) {
                Text(Self.time(draggedFraction.map { $0 * duration } ?? elapsed))
                Spacer(minLength: 4)
                Text(Self.time(duration))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded())
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
