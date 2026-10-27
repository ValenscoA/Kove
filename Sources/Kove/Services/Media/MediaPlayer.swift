import AppKit
import Foundation

/// The track a player is sitting on. Shared by every adapter.
struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var persistentID: String
    /// Direct artwork URL, when the player exposes one (Spotify does, Music does not).
    var artworkURL: String? = nil
}

enum PlaybackState: String {
    case stopped
    case playing
    case paused
}

struct PlayerSnapshot: Equatable {
    var state: PlaybackState
    var track: TrackInfo?
    var position: Double
}

enum PlayerReadResult {
    case snapshot(PlayerSnapshot)
    /// macOS is waiting for the user to allow Automation access.
    case permissionDenied
    case failed
}

/// One app that can publish playback.
///
/// Adapters are the only place that knows how a particular player is driven;
/// everything above them works on snapshots, so adding a player means adding a file.
/// Reads block and must be called off the main thread.
protocol MediaPlayer: AnyObject {
    /// Also the app's bundle identifier — stable, and used for artwork keys.
    var bundleID: String { get }
    /// Shown in the UI, e.g. when Automation access has not been granted.
    var displayName: String { get }

    var isRunning: Bool { get }

    /// Distributed notifications the player posts when playback changes. Used as a
    /// fast path so the island does not have to wait for the next poll.
    var changeNotifications: [Notification.Name] { get }

    func snapshot(timeout: TimeInterval) -> PlayerReadResult
    func artworkData(for track: TrackInfo, timeout: TimeInterval) -> Data?

    /// Explicit rather than a toggle: the caller has already decided the state, and a
    /// race with the player's own state would flip it back.
    func setPlaying(_ playing: Bool)
    func next()
    func previous()
    func seek(to seconds: Double)

    /// Brings the app to the front, launching it if needed.
    func activate()
}

enum ScriptField {
    /// ASCII unit separator — never appears in track metadata.
    static let separator = "\u{1F}"
}

extension MediaPlayer {
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func activate() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Small helper for the one adapter that has to download artwork itself.
enum ArtworkFetch {
    static func synchronously(_ urlString: String?, timeout: TimeInterval) -> Data? {
        guard let urlString, let url = URL(string: urlString) else { return nil }

        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            box.store(data)
            semaphore.signal()
        }
        task.resume()

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            return nil
        }
        return box.value
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Data?

        func store(_ data: Data?) {
            lock.lock()
            storage = data
            lock.unlock()
        }

        var value: Data? {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
