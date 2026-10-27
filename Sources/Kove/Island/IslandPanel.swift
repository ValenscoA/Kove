import AppKit
import SwiftUI

/// Borderless, never-key panel: clicks reach it without stealing focus.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel never takes focus, so every click counts as a "first mouse" in
/// AppKit terms. Without opting in, clicks are swallowed instead of delivered.
final class IslandHostingView<Content: View>: NSHostingView<Content> {

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// Hosts the SwiftUI island and limits hit testing to the island itself,
/// so the transparent parts of the panel stay click-through.
final class IslandContainerView: NSView {

    var islandSizeProvider: (() -> CGSize)?

    override var isFlipped: Bool { false }

    func islandRect(for size: CGSize) -> CGRect {
        CGRect(x: (bounds.width - size.width) / 2,
               y: bounds.height - size.height,
               width: size.width,
               height: size.height)
    }

    private var currentIslandRect: CGRect? {
        guard let size = islandSizeProvider?() else { return nil }
        return islandRect(for: size)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard let rect = currentIslandRect, rect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
