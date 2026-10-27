import AppKit
import SwiftUI

/// The app's preferences window.
///
/// Kove runs as an accessory (no Dock icon, no app menu), so there is no `Settings`
/// scene to hang this off: the menu bar item opens it instead.
final class SettingsWindowController {

    private let window: NSWindow

    init(controller: IslandController, preferences: IslandPreferences) {
        let root = SettingsView(controller: controller, preferences: preferences)
        let hosting = NSHostingController(rootView: root)
        // Let the SwiftUI layout decide the window height instead of hard-coding it.
        hosting.sizingOptions = [.preferredContentSize]

        window = NSWindow(contentViewController: hosting)
        window.title = "Kove Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.preferredContentSize)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        window.setFrameAutosaveName("KoveSettingsWindow")
    }

    func show() {
        // Opened from a menu bar click, so the window has to be brought forward
        // itself — an accessory app never becomes active on its own.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
