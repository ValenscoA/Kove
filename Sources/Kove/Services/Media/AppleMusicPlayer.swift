import Foundation

/// Apple Music over Apple Events.
final class AppleMusicPlayer: MediaPlayer {

    let bundleID = "com.apple.Music"
    let displayName = "Music"

    var changeNotifications: [Notification.Name] {
        [Notification.Name("com.apple.Music.playerInfo")]
    }

    func snapshot(timeout: TimeInterval) -> PlayerReadResult {
        let result = AppleScriptRunner.run(Scripts.state, timeout: timeout)
        guard result.succeeded else {
            return result.isPermissionDenied ? .permissionDenied : .failed
        }

        let fields = result.output
            .split(separator: Character(ScriptField.separator), omittingEmptySubsequences: false)
            .map(String.init)

        guard let stateText = fields.first else { return .failed }

        switch stateText {
        case "playing", "paused":
            guard fields.count >= 7 else { return .failed }
            return .snapshot(
                PlayerSnapshot(
                    state: stateText == "playing" ? .playing : .paused,
                    track: TrackInfo(
                        title: fields[1],
                        artist: fields[2],
                        album: fields[3],
                        duration: Double(fields[4]) ?? 0,
                        persistentID: fields[6]
                    ),
                    position: Double(fields[5]) ?? 0
                )
            )
        default:
            return .snapshot(PlayerSnapshot(state: .stopped, track: nil, position: 0))
        }
    }

    /// Music returns artwork only as Apple Event data, so it is written to a file
    /// and read back — the one thing Spotify's adapter does not have to do.
    func artworkData(for track: TrackInfo, timeout: TimeInterval) -> Data? {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kove-artwork-\(track.persistentID).img").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = AppleScriptRunner.run(Scripts.artwork(path: path), timeout: timeout)
        guard result.succeeded, result.output == "ok" else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    func setPlaying(_ playing: Bool) { run(playing ? "play" : "pause") }
    func next() { run("next track") }
    func previous() { run("previous track") }

    func seek(to seconds: Double) {
        run("set player position to \(String(format: "%.2f", seconds))")
    }

    private func run(_ body: String) {
        _ = AppleScriptRunner.run("tell application \"Music\" to \(body)", timeout: 4)
    }

    private enum Scripts {
        static let state = """
        tell application "Music"
            set sep to (ASCII character 31)
            try
                set pstate to (player state as text)
            on error
                set pstate to "stopped"
            end try
            if pstate is "stopped" then return pstate
            try
                set t to current track
            on error
                return pstate
            end try
            set nm to ""
            try
                set nm to (name of t)
            end try
            set ar to ""
            try
                set ar to (artist of t)
            end try
            set al to ""
            try
                set al to (album of t)
            end try
            set du to 0
            try
                set du to (duration of t)
            end try
            set ps to 0
            try
                set ps to (player position)
            end try
            set pid to ""
            try
                set pid to (persistent ID of t)
            end try
            return pstate & sep & nm & sep & ar & sep & al & sep & (du as text) & sep & (ps as text) & sep & pid
        end tell
        """

        static func artwork(path: String) -> String {
            """
            tell application "Music"
                set t to current track
                if (count of artworks of t) is 0 then return "none"
                set d to (data of artwork 1 of t)
                set f to open for access (POSIX file "\(path)") with write permission
                set eof f to 0
                write d to f
                close access f
                return "ok"
            end tell
            """
        }
    }
}
