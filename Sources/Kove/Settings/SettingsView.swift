import SwiftUI

struct SettingsView: View {

    @ObservedObject var controller: IslandController
    @ObservedObject var preferences: IslandPreferences

    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 520

    /// Explicit rather than semantic (`windowBackgroundColor` and
    /// `controlBackgroundColor` can collapse to the same white): the rows need to
    /// read as cards on a slightly darker pane.
    private var windowBackground: Color {
        colorScheme == .dark ? Color(white: 0.115) : Color(white: 0.925)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.165) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            IslandPreviewCard(
                enabled: controller.enabledSources,
                active: controller.enabledSources.contains(controller.mode) ? controller.mode : nil
            )

            group("Show on the island") {
                SettingsRow(
                    symbol: IslandMode.music.symbolName,
                    title: IslandMode.music.title,
                    subtitle: "Artwork, track details and playback controls.",
                    isOn: sourceBinding(.music)
                )

                SettingsDivider()

                SettingsRow(
                    symbol: IslandMode.commandCode.symbolName,
                    title: IslandMode.commandCode.title,
                    subtitle: "Session and weekly credit usage for Command Code.",
                    isOn: sourceBinding(.commandCode)
                )
            }

            group("Behaviour") {
                SettingsRow(
                    symbol: "rectangle.inset.filled",
                    title: "Hide over full-screen apps",
                    subtitle: "Steps aside while an app occupies the whole display.",
                    isOn: $preferences.hideOverFullScreen
                )
            }

            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: Self.width)
        .background(windowBackground)
    }

    // MARK: Sections

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Changes apply immediately.")
            Spacer(minLength: 12)
            Text("Kove \(Self.version)")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    // MARK: Bindings

    /// Flipping a source also decides which one the island shows, which is
    /// `IslandController`'s job rather than the preferences'.
    private func sourceBinding(_ source: IslandMode) -> Binding<Bool> {
        Binding(
            get: { controller.isSourceEnabled(source) },
            set: { controller.setSourceEnabled(source, $0) }
        )
    }

    static let version = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
}

// MARK: - Rows

struct SettingsRow: View {

    let symbol: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 51)
    }
}
