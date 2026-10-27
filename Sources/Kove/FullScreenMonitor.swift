import AppKit

/// Detects whether this display is currently occupied by a full-screen app.
///
/// Geometry alone can't tell full screen from a merely maximised window — both
/// occupy the visible frame. What is unique to full screen is that the app owns
/// a window pinned to the display's top edge, over the strip macOS reserves for
/// the menu bar, which a normal window can never cover.
///
/// That shows up in one of two shapes, depending on the app and on whether the
/// display has a notch housing:
///
///   * one window covering the whole display (apps that hide the menu bar), or
///   * a separate full-width strip window above the content window (native
///     full screen on a notched display).
///
/// Both are full-width windows at the display's top edge, so that is the shape
/// to look for. Menu bar chrome (Window Server, Control Center, status items)
/// covers that strip too, but it lives above the normal window layer, where it
/// is only counted when it belongs to the frontmost app.
enum FullScreenMonitor {

    static func isFullScreen(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let display = displayBounds(for: screen)
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let frontPID = NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) }

        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int, pid != ownPID else { continue }

            // Normal app windows always count. Anything above that layer is menu
            // bar chrome — the Dock, Control Center, other status items — unless
            // it is the frontmost app's own full-screen strip.
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 || pid == frontPID else { continue }

            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )

            if rect.minX <= display.minX + 2,
               rect.minY <= display.minY + 2,
               rect.maxX >= display.maxX - 2 {
                return true
            }
        }
        return false
    }

    /// Window server coordinates put the origin at the top-left of the primary
    /// display, so AppKit screen frames have to be flipped against that one —
    /// not against whichever display happens to sit highest.
    private static func displayBounds(for screen: NSScreen) -> CGRect {
        let primary = NSScreen.screens.first ?? screen
        return CGRect(
            x: screen.frame.minX,
            y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}
