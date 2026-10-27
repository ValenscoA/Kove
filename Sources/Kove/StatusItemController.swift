import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onOpenPlayer: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let isExpanded: () -> Bool
    private let canExpand: () -> Bool

    private let toggleItem = NSMenuItem(title: "Expand Island", action: nil, keyEquivalent: "")

    init(
        onToggle: @escaping () -> Void,
        onOpenPlayer: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        isExpanded: @escaping () -> Bool,
        canExpand: @escaping () -> Bool
    ) {
        self.onToggle = onToggle
        self.onOpenPlayer = onOpenPlayer
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.isExpanded = isExpanded
        self.canExpand = canExpand
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = Self.statusBarImage()
                ?? NSImage(systemSymbolName: "capsule.portrait.fill", accessibilityDescription: "Kove")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Kove"
        }

        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Kove", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggleIsland)
        menu.addItem(toggleItem)

        let playerItem = NSMenuItem(title: "Open Player", action: #selector(openPlayer), keyEquivalent: "")
        playerItem.target = self
        menu.addItem(playerItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Kove", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// The app's own mark as a template image, assembled from the loose PNGs so the
    /// @2x/@3x reps are picked up on Retina. Falls back to an SF Symbol when running
    /// the raw binary, which has no bundle resources.
    private static func statusBarImage() -> NSImage? {
        let points = NSSize(width: 18, height: 18)
        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }

        for scale in [2, 3] {
            guard let url = Bundle.main.url(forResource: "StatusIcon@\(scale)x", withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data)
            else { continue }
            // Pixel dimensions stay as rendered; the logical size stays 18 pt.
            rep.size = points
            image.addRepresentation(rep)
        }

        image.size = points
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.isEnabled = canExpand()
        toggleItem.title = isExpanded() ? "Collapse Island" : "Expand Island"
    }

    @objc private func toggleIsland() { onToggle() }
    @objc private func openPlayer() { onOpenPlayer() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}
