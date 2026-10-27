import AppKit
import Foundation
import ImageIO
import SwiftUI

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var persistentID: String
}

/// Reads and controls Music.app over AppleScript.
///
/// Apple Events to Music cost ~80 ms per round trip, so the state poll runs on a
/// lazy schedule and the playback position is interpolated locally between polls.
final class MusicService: ObservableObject {

    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    @Published private(set) var isMusicRunning = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "com.kove.island.applescript", qos: .userInitiated)
    private var pollWork: DispatchWorkItem?
    private var isActive = false

    private static let musicBundleID = "com.apple.Music"
    /// Posted by Music whenever playback state, the current track or the player
    /// position changes.
    private static let playerInfoNotification = NSNotification.Name("com.apple.Music.playerInfo")

    private var distributedObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var playerInfoRefresh: DispatchWorkItem?

    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var seeking = false

    private var artworkID: String?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkOrder: [String] = []

    var hasTrack: Bool { track != nil }

    var position: Double {
        guard isPlaying, !seeking, let duration = track?.duration else { return anchorPosition }
        return min(duration, anchorPosition + Date().timeIntervalSince(anchorDate))
    }

    var progress: Double {
        guard let duration = track?.duration, duration > 0 else { return 0 }
        return max(0, min(1, position / duration))
    }

    // MARK: Lifecycle

    func start() {
        guard !isActive else { return }
        isActive = true
        observePlayerInfo()
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

    // MARK: Change notifications

    /// Music broadcasts each change, so reacting to it turns a poll that may be
    /// seconds away into a single Apple Event: the island appears while the play
    /// click is still on screen. The timer below stays as the backstop, since a
    /// notification is only ever an optimisation — if macOS stops posting it,
    /// everything still works, just with the old latency.
    private func observePlayerInfo() {
        guard distributedObserver == nil else { return }

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.playerInfoNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSoon()
        }

        // Music being launched or quit is worth reacting to immediately too, so
        // "open Music, hit play" does not have to wait out an idle poll.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.musicBundleID
                else { return }
                self?.refreshSoon()
            }
            workspaceObservers.append(token)
        }
    }

    private func removeObservers() {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()

        playerInfoRefresh?.cancel()
        playerInfoRefresh = nil
    }

    /// One user action produces a burst of notifications; coalesce them into a
    /// single AppleScript round trip.
    private func refreshSoon() {
        guard isActive else { return }
        playerInfoRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performPoll() }
        playerInfoRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    // MARK: Polling

    private func nextDelay() -> TimeInterval {
        if permissionDenied { return 8 }
        if !isMusicRunning { return 2.5 }
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

        // A notification-driven refresh may already have a timer pending; drop it
        // so one change never queues two Apple Events.
        pollWork?.cancel()
        pollWork = nil

        let running = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.musicBundleID)
            .isEmpty

        guard running else {
            isMusicRunning = false
            applyIdle()
            poll()
            return
        }
        isMusicRunning = true

        queue.async { [weak self] in
            let result = AppleScriptRunner.run(MusicScripts.state)
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                self.handleState(result)
                self.poll()
            }
        }
    }

    private func handleState(_ result: AppleScriptResult) {
        guard result.succeeded else {
            if result.isPermissionDenied { permissionDenied = true }
            return
        }
        permissionDenied = false

        let fields = result.output
            .split(separator: Character(MusicScripts.separator), omittingEmptySubsequences: false)
            .map(String.init)

        guard let playerState = fields.first else { return }

        switch playerState {
        case "playing", "paused":
            guard fields.count >= 7 else { return }
            let info = TrackInfo(
                title: fields[1],
                artist: fields[2],
                album: fields[3],
                duration: Double(fields[4]) ?? 0,
                persistentID: fields[6]
            )
            isPlaying = playerState == "playing"
            track = info
            anchorPosition = Double(fields[5]) ?? 0
            anchorDate = Date()
            seeking = false
            if artworkID != info.persistentID {
                loadArtwork(for: info)
            }
        default:
            applyIdle()
        }
    }

    private func applyIdle() {
        if track != nil { track = nil }
        if artwork != nil { artwork = nil }
        artworkID = nil
        isPlaying = false
        seeking = false
        anchorPosition = 0
    }

    // MARK: Artwork

    private func loadArtwork(for info: TrackInfo) {
        artworkID = info.persistentID
        let id = info.persistentID

        if let cached = artworkCache[id] {
            artwork = cached
            return
        }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kove-artwork-\(id).img").path
        let script = MusicScripts.artwork(path: path)

        queue.async { [weak self] in
            let result = AppleScriptRunner.run(script, timeout: 6)
            var image: NSImage?
            if result.succeeded, result.output == "ok" {
                image = Self.decodeArtwork(at: path)
            }
            try? FileManager.default.removeItem(atPath: path)

            DispatchQueue.main.async {
                guard let self, self.artworkID == id, let image else { return }
                self.storeArtwork(image, for: id)
                withAnimation(.easeOut(duration: 0.18)) { self.artwork = image }
            }
        }
    }

    /// Music exports artwork at full resolution, and `NSImage(contentsOfFile:)`
    /// defers decoding to the first draw — which lands on the main thread exactly
    /// as the island expands. Downsample to a bitmap here, on the AppleScript
    /// queue, so the thumbnail is ready to composite.
    private static func decodeArtwork(at path: String) -> NSImage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 288,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary)
        else { return nil }

        return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
    }

    private func storeArtwork(_ image: NSImage, for id: String) {
        if artworkCache[id] == nil {
            artworkOrder.append(id)
            if artworkOrder.count > 8 {
                let evicted = artworkOrder.removeFirst()
                artworkCache[evicted] = nil
            }
        }
        artworkCache[id] = image
    }

    // MARK: Controls

    func togglePlayPause() {
        isPlaying.toggle()
        anchorDate = Date()
        send(isPlaying ? "play" : "pause")
    }

    func next() {
        send("next track")
    }

    func previous() {
        send("previous track")
    }

    func seek(to seconds: Double) {
        guard let duration = track?.duration else { return }
        let target = max(0, min(duration, seconds))
        anchorPosition = target
        anchorDate = Date()
        seeking = true
        send("set player position to \(String(format: "%.2f", target))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.seeking = false
        }
    }

    func openMusic() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
    }
    private func send(_ body: String) {
        queue.async { [weak self] in
            _ = AppleScriptRunner.run(MusicScripts.command(body), timeout: 4)
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.performPoll() }
            }
        }
    }
}
