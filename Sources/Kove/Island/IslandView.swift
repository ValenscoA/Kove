import SwiftUI

struct IslandView: View {
    @ObservedObject var controller: IslandController
    @ObservedObject var media: MediaService
    @ObservedObject var usage: CommandCodeUsageService

    private var expanded: Bool { controller.isExpanded }
    private var size: CGSize { expanded ? controller.expandedSize : controller.collapsedSize }
    private var shape: IslandShape {
        IslandShape(bottomCornerRadius: expanded ? 26 : 12)
    }

    /// Expanding may overshoot playfully; collapsing must not, or the pill
    /// shrinks past the notch and stops covering it mid-animation.
    private var animation: Animation {
        expanded
            ? .spring(response: 0.36, dampingFraction: 0.74)
            : .spring(response: 0.30, dampingFraction: 1)
    }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }

    /// Only the pill's own geometry animates. Both content layouts keep the
    /// geometry they will have when the animation ends and simply cross-fade into
    /// it: animating their frame instead re-proposed the text every frame, so
    /// every label was re-truncated at a slightly different width sixty times a
    /// second — that is what made the expansion stutter.
    private var island: some View {
        ZStack(alignment: .top) {
            if expanded {
                ExpandedView(
                    media: media,
                    usage: usage,
                    mode: controller.mode,
                    enabledSources: controller.enabledSources,
                    stripHeight: max(controller.notchHeight, 26),
                    onSelectMode: { controller.setMode($0) }
                )
                .frame(
                    width: controller.expandedSize.width,
                    height: controller.expandedSize.height,
                    alignment: .top
                )
                .transition(.opacity)
            } else {
                CollapsedView(
                    media: media,
                    usage: usage,
                    mode: controller.mode,
                    notchWidth: controller.notchWidth
                )
                .frame(
                    width: controller.collapsedSize.width,
                    height: controller.collapsedSize.height,
                    alignment: .top
                )
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.03)],
                    startPoint: .bottom,
                    endPoint: .top
                ),
                lineWidth: 0.7
            )
            .allowsHitTesting(false)
        )
        .contentShape(shape)
        .onTapGesture { controller.toggle() }
        .animation(animation, value: expanded)
    }
}
