import AppKit
import Foundation
import ImageIO
import SwiftUI

/// Surfaces whatever the system's players are doing, whichever app it is.
///
/// Apple Events to a player cost ~80 ms per round trip, so state is read on a lazy
/// schedule; the playback position is interpolated locally between polls, and each
/// player's change notification is a fast path around the schedule.
final class MediaService: ObservableObject {

    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPlayerRunning = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var permissionDenied = false
    /// Which player denied Automation access, so the message can name it.
    @Published private(set) var deniedPlayerName: String?
    /// The player currently driving the island.
    @Published private(set) var activePlayerName: String?

    var hasTrack: Bool { track != nil }

    var position: Double {
        guard isPlaying, !seeking, let duration = track?.duration else { return anchorPosition }
        return min(duration, anchorPosition + Date().timeIntervalSince(anchorDate))
    }

    var progress: Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return max(0, min(1, position / duration))
    }

    private let queue = DispatchQueue(label: "com.kove.media.scripts", qos: .userInitiated)
    private let players: [MediaPlayer]
    private var activePlayer: MediaPlayer?
    private var pollWork: DispatchWorkItem?
    private var isActive = false

    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var seeking = false

    private var artworkKey: String?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkOrder: [String] = []

    private var notificationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var notificationRefresh: DispatchWorkItem?

    init(players: [MediaPlayer] = [AppleMusicPlayer(), SpotifyPlayer()]) {
        self.players = players
    }

    // MARK: Lifecycle

    func start() {
        guard !isActive else { return }
        isActive = true
        observePlayers()
        poll()
    }

    func stop() {
        isActive = false
        pollWork?.cancel()
        pollWork = nil
        removeObservers()
    }

    deinit {
        removeObservers()
    }

    // MARK: Polling

    private func nextDelay() -> TimeInterval {
        if permissionDenied { return 8 }
        if !isPlayerRunning { return 2.5 }
        return isPlaying ? 1.8 : 2.5
    }

    private func poll() {
        guard isActive else { return }
        pollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performPoll() }
        pollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay(), execute: work)
    }

    private func performPoll() {
        guard isActive else { return }

        // A notification-driven refresh may already have a timer pending; drop it so
        // one change never queues a second round trip.
        pollWork?.cancel()
        pollWork = nil

        // Checking whether an app is running is far cheaper than scripting it, so
        // players that are not open cost nothing.
        let running = players.filter(\.isRunning)
        isPlayerRunning = !running.isEmpty

        guard !running.isEmpty else {
            applyIdle()
            poll()
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let results = running.map { ($0, $0.snapshot(timeout: 5)) }
            DispatchQueue.main.async {
                guard self.isActive else { return }
                self.handle(results)
                self.poll()
            }
        }
    }

    private func handle(_ results: [(MediaPlayer, PlayerReadResult)]) {
        var candidates: [(MediaPlayer, PlayerSnapshot)] = []
        var denied: MediaPlayer?

        for (player, result) in results {
            switch result {
            case .snapshot(let snapshot):
                if snapshot.state != .stopped,
                   let info = snapshot.track,
                   !info.title.isEmpty {
                    candidates.append((player, snapshot))
                }
            case .permissionDenied:
                if denied == nil { denied = player }
            case .failed:
                break
            }
        }

        permissionDenied = candidates.isEmpty && denied != nil
        deniedPlayerName = denied?.displayName

        guard let (player, snapshot) = choose(from: candidates) else {
            applyIdle()
            return
        }

        activePlayer = player
        activePlayerName = player.displayName
        isPlaying = snapshot.state == .playing

        if let info = snapshot.track {
            if track != info { track = info }
            let key = "\(player.bundleID)|\(info.persistentID)"
            if artworkKey != key { loadArtwork(for: info, player: player, key: key) }
        }

        anchorPosition = snapshot.position
        anchorDate = Date()
        seeking = false
    }

    /// Playing beats paused; a paused player stays on screen until something else
    /// plays, so the pill does not jump between two idle players.
    private func choose(from candidates: [(MediaPlayer, PlayerSnapshot)]) -> (MediaPlayer, PlayerSnapshot)? {
        let playing = candidates.filter { $0.1.state == .playing }

        if !playing.isEmpty {
            if let current = activePlayer, let match = playing.first(where: { $0.0 === current }) {
                return match
            }
            return playing.first
        }

        if let current = activePlayer, let match = candidates.first(where: { $0.0 === current }) {
            return match
        }
        return candidates.first
    }

    private func applyIdle() {
        if track != nil { track = nil }
        if artwork != nil { artwork = nil }
        artworkKey = nil
        isPlaying = false
        seeking = false
        anchorPosition = 0
    }

    // MARK: Change notifications

    /// Every player posts a distributed notification when playback changes, which
    /// turns a poll that may be seconds away into a single Apple Event. The timer
    /// remains the backstop: a notification is only ever an optimisation.
    private func observePlayers() {
        guard notificationObservers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        for name in players.flatMap(\.changeNotifications) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshSoon()
            }
            notificationObservers.append(token)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        let ids = Set(players.map(\.bundleID))
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let id = app.bundleIdentifier,
                      ids.contains(id)
                else { return }
                self?.refreshSoon()
            }
            workspaceObservers.append(token)
        }
    }

    private func removeObservers() {
        let center = DistributedNotificationCenter.default()
        notificationObservers.forEach(center.removeObserver)
        notificationObservers.removeAll()

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()

        notificationRefresh?.cancel()
        notificationRefresh = nil
    }

    /// One user action produces a burst of notifications; coalesce them into a
    /// single round trip.
    private func refreshSoon() {
        guard isActive else { return }
        notificationRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performPoll() }
        notificationRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    // MARK: Artwork

    private func loadArtwork(for info: TrackInfo, player: MediaPlayer, key: String) {
        artworkKey = key

        if let cached = artworkCache[key] {
            artwork = cached
            return
        }

        queue.async { [weak self] in
            let data = player.artworkData(for: info, timeout: 6)
            let image = data.flatMap(Self.downsample)

            DispatchQueue.main.async {
                guard let self, self.artworkKey == key, let image else { return }
                self.storeArtwork(image, for: key)
                withAnimation(.easeOut(duration: 0.18)) { self.artwork = image }
            }
        }
    }

    /// Players hand over full-resolution artwork, and `NSImage(data:)` defers decoding
    /// to the first draw — which lands on the main thread exactly as the island
    /// expands. Downsample to a bitmap here, on the script queue.
    private static func downsample(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 288,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary)
        else { return nil }

        return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
    }

    private func storeArtwork(_ image: NSImage, for key: String) {
        if artworkCache[key] == nil {
            artworkOrder.append(key)
            if artworkOrder.count > 8 {
                let evicted = artworkOrder.removeFirst()
                artworkCache[evicted] = nil
            }
        }
        artworkCache[key] = image
    }

    // MARK: Controls

    func togglePlayPause() {
        guard activePlayer != nil else { return }
        let wanted = !isPlaying
        isPlaying = wanted
        anchorDate = Date()
        send { $0.setPlaying(wanted) }
    }

    func next() { send { $0.next() } }
    func previous() { send { $0.previous() } }

    func seek(to seconds: Double) {
        guard let duration = track?.duration else { return }
        let target = max(0, min(duration, seconds))
        anchorPosition = target
        anchorDate = Date()
        seeking = true
        send { $0.seek(to: target) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.seeking = false
        }
    }

    /// Opens the player that is driving the island, or Apple Music if none is.
    func openPlayer() {
        let target = activePlayer ?? players.first(where: \.isRunning) ?? players[0]
        target.activate()
    }

    private func send(_ command: @escaping (MediaPlayer) -> Void) {
        guard let player = activePlayer else { return }
        queue.async { [weak self] in
            command(player)
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.performPoll() }
            }
        }
    }
}
