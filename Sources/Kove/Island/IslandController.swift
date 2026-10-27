import AppKit
import Combine

enum IslandMode: String, CaseIterable {
    case music
    case commandCode

    /// Label used by the menu bar submenu.
    var title: String {
        switch self {
        case .music: return "Now Playing"
        case .commandCode: return "Command Code Usage"
        }
    }

    /// Icon used by the island's own switcher.
    var symbolName: String {
        switch self {
        case .music: return "music.note"
        case .commandCode: return "chart.bar.xaxis"
        }
    }

    var helpText: String {
        switch self {
        case .music: return "Show what's playing, from any player"
        case .commandCode: return "Show Command Code usage"
        }
    }
}

/// Owns the island's geometry and expansion state. Main thread only.
final class IslandController: ObservableObject {

    @Published private(set) var isExpanded = false
    @Published private(set) var mode: IslandMode

    /// Mirrors `IslandPreferences.enabledSources` so SwiftUI views observing the
    /// controller refresh as soon as a source is toggled in the menu bar.
    @Published private(set) var enabledSources: Set<IslandMode>

    private let preferences: IslandPreferences
    private var preferencesCancellable: AnyCancellable?

    init(preferences: IslandPreferences = .shared) {
        self.preferences = preferences
        enabledSources = preferences.enabledSources

        let stored = UserDefaults.standard.string(forKey: Self.modeKey)
        let remembered = IslandMode(rawValue: stored ?? "") ?? .music
        // A remembered mode may have been switched off from the menu bar since
        // the last launch; fall back to whatever is still allowed.
        mode = preferences.isEnabled(remembered)
            ? remembered
            : (preferences.enabledSources.first ?? remembered)

        preferencesCancellable = preferences.$enabledSources
            .sink { [weak self] sources in
                guard let self else { return }
                self.enabledSources = sources
                if sources.isEmpty {
                    self.setExpanded(false)
                } else if !sources.contains(self.mode), let replacement = sources.first {
                    self.setMode(replacement)
                }
            }
    }

    @Published private(set) var collapsedSize = CGSize(width: 249, height: 32)
    @Published private(set) var expandedSize = CGSize(width: 420, height: 178)

    private(set) var notchWidth: CGFloat = 185
    private(set) var notchHeight: CGFloat = 32
    private(set) var islandCenterX: CGFloat = 0

    static let collapsedWing: CGFloat = 32
    static let contentHeight: CGFloat = 146
    private static let modeKey = "islandMode"

    func adopt(screen: NSScreen) {
        let notch = Self.notchRect(on: screen)
        notchWidth = notch?.width ?? 0
        notchHeight = notch?.height ?? 0
        islandCenterX = notch?.midX ?? screen.frame.midX

        let hasNotch = (notch?.width ?? 0) > 0
        collapsedSize = hasNotch
            ? CGSize(width: notchWidth + Self.collapsedWing * 2, height: notchHeight)
            : CGSize(width: 220, height: 30)

        let strip = hasNotch ? notchHeight : 26
        expandedSize = CGSize(width: 420, height: strip + Self.contentHeight)
    }

    func setExpanded(_ value: Bool) {
        guard isExpanded != value else { return }
        isExpanded = value
    }

    func toggle() { setExpanded(!isExpanded) }

    /// False when every source has been switched off, which hides the pill.
    var hasEnabledSource: Bool { !enabledSources.isEmpty }

    func isSourceEnabled(_ source: IslandMode) -> Bool {
        enabledSources.contains(source)
    }

    /// Ticking a source makes it the one on screen; unticking the visible source
    /// leaves whatever else is still enabled showing.
    func setSourceEnabled(_ source: IslandMode, _ enabled: Bool) {
        preferences.setEnabled(source, enabled)
        if enabled { setMode(source) }
    }

    func setMode(_ value: IslandMode) {
        guard mode != value else { return }
        mode = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.modeKey)
    }

    /// The notch is the gap between the two menu bar areas Apple reports.
    static func notchRect(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        let height = screen.safeAreaInsets.top
        return CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height)
    }

    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { notchRect(on: $0) != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
