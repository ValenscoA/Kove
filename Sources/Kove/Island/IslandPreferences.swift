import Combine
import Foundation

/// Which content sources the island is allowed to show, persisted so the choice
/// survives relaunches. The menu bar submenu and the island's own switcher both
/// read from here, so they can never disagree.
final class IslandPreferences: ObservableObject {

    static let shared = IslandPreferences()

    /// Sources the user has left enabled. An empty set is a valid choice: it
    /// means "show nothing", and the pill hides itself until a source comes back.
    @Published private(set) var enabledSources: Set<IslandMode> {
        didSet { store() }
    }

    /// Whether the island steps aside for full-screen apps. Off means it keeps
    /// hovering over them.
    @Published var hideOverFullScreen: Bool {
        didSet { defaults.set(hideOverFullScreen, forKey: Self.fullScreenKey) }
    }

    private static let key = "enabledIslandSources"
    private static let fullScreenKey = "hideOverFullScreen"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.array(forKey: Self.key) as? [String] {
            enabledSources = Set(stored.compactMap(IslandMode.init(rawValue:)))
        } else {
            // No stored choice yet: show everything, as the island always has.
            enabledSources = Set(IslandMode.allCases)
        }

        hideOverFullScreen = defaults.object(forKey: Self.fullScreenKey) as? Bool ?? true
    }

    func isEnabled(_ source: IslandMode) -> Bool {
        enabledSources.contains(source)
    }

    func setEnabled(_ source: IslandMode, _ enabled: Bool) {
        var updated = enabledSources
        if enabled {
            updated.insert(source)
        } else {
            updated.remove(source)
        }
        guard updated != enabledSources else { return }
        enabledSources = updated
    }

    private func store() {
        defaults.set(enabledSources.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
