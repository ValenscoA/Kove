import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: IslandController!
    private var music: MusicService!
    private var usage: CommandCodeUsageService!
    private var panel: IslandPanel!
    private var container: IslandContainerView!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController!
    private var playbackCancellable: AnyCancellable?
    private var modeCancellable: AnyCancellable?
    private var sourceCancellable: AnyCancellable?
    private var fullScreenCancellable: AnyCancellable?

    private let preferences = IslandPreferences.shared

    /// The panel is faded in and out rather than toggled, so a space or app
    /// switch never makes it blink over the transition animation.
    private enum PanelState { case hidden, appearing, visible, disappearing }
    private var panelState: PanelState = .hidden

    /// Grace period after a space/app change, sampled instead of guessed: macOS
    /// reports the change at inconsistent moments (sometimes mid-animation,
    /// sometimes only once it has finished).
    private var settleTimer: Timer?
    private var settleTicks = 0
    private var cleanTicks = 0

    /// Backstop for the space and full-screen notifications, which macOS does not
    /// deliver reliably on every version. Two window-server queries a second are
    /// cheap, and they guarantee that a missed notification cannot leave the
    /// island sitting on top of a full-screen app.
    private var watchdogTimer: Timer?

    private let settleTickInterval: TimeInterval = 0.1
    private let settleTickCount = 15
    private let quietTicksBeforeShowing = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        music = MusicService()
        usage = CommandCodeUsageService()
        controller = IslandController(preferences: preferences)

        let initialFrame = CGRect(x: 0, y: 0, width: 640, height: 300)
        container = IslandContainerView(frame: initialFrame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.autoresizingMask = [.width, .height]

        let hosting = IslandHostingView(
            rootView: IslandView(controller: controller, music: music, usage: usage)
        )
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.islandSizeProvider = { [weak self] in
            guard let self else { return .zero }
            return self.controller.isExpanded ? self.controller.expandedSize : self.controller.collapsedSize
        }

        panel = IslandPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        layout()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(spaceOrAppChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(spaceOrAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        music.start()

        syncServices()

        modeCancellable = controller.$mode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncServices()
                self.settle()
            }

        playbackCancellable = music.$isPlaying
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.settle(showImmediately: playing) }

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.controller.toggle() },
            onOpenMusic: { [weak self] in self?.music.openMusic() },
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onQuit: { NSApp.terminate(nil) },
            isExpanded: { [weak self] in self?.controller.isExpanded ?? false },
            canExpand: { [weak self] in self?.canExpandIsland ?? false }
        )

        settingsWindow = SettingsWindowController(controller: controller, preferences: preferences)

        // The settings window and the island share `IslandPreferences`, so react to
        // changes here instead of at each call site.
        sourceCancellable = controller.$enabledSources
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncServices()
                self.settle()
            }

        fullScreenCancellable = preferences.$hideOverFullScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settle() }

        // Login items launch while the desktop is still fading in from the login
        // window, and anything ordered in during that fade sits on top of it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.startWatchdog()
            #if DEBUG
            // Screenshot helpers: `Kove --expand` opens the island straight away,
            // `--dark` forces the dark appearance for window captures.
            if CommandLine.arguments.contains("--expand") {
                self.controller.setExpanded(true)
            }
            if CommandLine.arguments.contains("--demo") {
                self.usage.stop()
                self.usage.useDemoSnapshot()
            }
            if CommandLine.arguments.contains("--dark") {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            } else if CommandLine.arguments.contains("--light") {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            #endif
            self.settle()
            // Handy while iterating on the window: `Kove --settings`.
            if CommandLine.arguments.contains("--settings") {
                self.settingsWindow.show()
            }
            #if DEBUG
            if CommandLine.arguments.contains("--render-settings") {
                self.renderSettingsMockup()
            }
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        usage.stop()
        settleTimer?.invalidate()
        watchdogTimer?.invalidate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc private func screenParametersChanged() {
        layout()
        settle()
    }

    /// Entering full screen moves the app's window over the menu bar strip, and
    /// that transition also triggers a screen-parameter change — the reason the
    /// island used to pop in for a few frames and then vanish again.
    @objc private func spaceOrAppChanged() {
        settle()
    }

    // MARK: Visibility

    #if DEBUG
    /// Dev helper: renders the settings window offscreen to a PNG so the layout can
    /// be reviewed without opening it. `Kove --render-settings /tmp/out.png`.
    private func renderSettingsMockup() {
        // Called from a main-queue block; ImageRenderer is main-actor bound.
        MainActor.assumeIsolated {
            defer { NSApp.terminate(nil) }

            let renderer = ImageRenderer(
                content: SettingsView(controller: controller, preferences: preferences)
                    .environment(
                        \.colorScheme,
                        CommandLine.arguments.contains("dark") ? .dark : .light
                    )
            )
            renderer.scale = 2

            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }

            let path = CommandLine.arguments.dropFirst().first { $0.hasSuffix(".png") }
                ?? "/tmp/kove-settings.png"
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
    #endif

    /// Command Code is only polled while it is both the visible source and
    /// switched on, so unticking it in the menu bar stops the network traffic.
    private func syncServices() {
        let wantsUsage = controller.mode == .commandCode && controller.isSourceEnabled(.commandCode)
        if wantsUsage {
            usage.start()
        } else {
            usage.stop()
        }
    }

    /// Expanding is pointless only while there is no track loaded at all; a paused
    /// track stays expandable so playback can be resumed from the island.
    private var canExpandIsland: Bool {
        guard controller.hasEnabledSource else { return false }
        if controller.mode == .music { return music.hasTrack }
        return true
    }

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.applyVisibility()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    /// `showImmediately` skips the quiet period when playback starts: that delay
    /// exists so a full-screen transition cannot flash the pill in, and starting a
    /// track is not a transition.
    private func settle(showImmediately: Bool = false) {
        cleanTicks = showImmediately ? quietTicksBeforeShowing : 0
        settleTicks = 0
        applyVisibility()

        settleTimer?.invalidate()
        let timer = Timer(timeInterval: settleTickInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.applyVisibility()
            self.settleTicks += 1
            if self.hasSettled {
                timer.invalidate()
                self.settleTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    /// Stop sampling as soon as the state is unambiguous instead of holding the
    /// timer for the whole grace period.
    private var hasSettled: Bool {
        if settleTicks >= settleTickCount { return true }
        if panelState == .visible, cleanTicks >= 6 { return true }
        if panelState == .hidden, cleanTicks == 0, settleTicks >= 6 { return true }
        return false
    }

    private func applyVisibility() {
        guard let screen = IslandController.preferredScreen() else { return }

        // Every source switched off from the menu bar: nothing to draw, and the
        // collapsed pill should not linger on the notch.
        if !controller.hasEnabledSource {
            cleanTicks = 0
            controller.setExpanded(false)
            hidePanel()
            return
        }

        // Music mode only exists to surface the current track, so no track at all
        // (Music stopped, quit, or never started) means nothing on screen. Paused
        // still counts as a track: the pill stays put so playback can be resumed
        // from it. Collapse first so playback resumes to the pill instead of an
        // expanded panel the user left open.
        if !music.hasTrack, controller.mode == .music {
            cleanTicks = 0
            controller.setExpanded(false)
            hidePanel()
            return
        }

        // Hiding is immediate: the island hovering over a transition is the
        // glitch, so there is nothing to gain from waiting. The user can also opt
        // out of stepping aside for full-screen apps altogether.
        if preferences.hideOverFullScreen, FullScreenMonitor.isFullScreen(on: screen) {
            cleanTicks = 0
            hidePanel()
            return
        }

        // Showing needs the desktop to stay clear for a moment. A transition can
        // look finished for a tick or two before the full-screen window lands,
        // and that brief look is enough to flash the pill in.
        cleanTicks += 1
        if cleanTicks >= quietTicksBeforeShowing {
            showPanel()
        }
    }

    private func showPanel() {
        switch panelState {
        case .visible, .appearing:
            return
        case .hidden:
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panelState = .appearing
        case .disappearing:
            panelState = .appearing
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self, self.panelState == .appearing else { return }
            self.panelState = .visible
        })
    }

    private func hidePanel() {
        switch panelState {
        case .hidden, .disappearing:
            return
        case .visible, .appearing:
            panelState = .disappearing
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panelState == .disappearing else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.panelState = .hidden
        })
    }

    /// Repositions the panel only — it never changes whether the panel is on
    /// screen. Screen-parameter changes arrive in the middle of full-screen
    /// transitions, so anything that shows the panel here re-introduces the flash.
    private func layout() {
        guard let screen = IslandController.preferredScreen() else { return }
        controller.adopt(screen: screen)

        let width = controller.expandedSize.width + 96
        let height = controller.expandedSize.height + 92
        let frame = CGRect(
            x: controller.islandCenterX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        panel.setFrame(frame, display: panelState != .hidden)
    }
}
