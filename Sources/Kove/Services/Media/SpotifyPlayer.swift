import Foundation

/// Spotify over Apple Events.
///
/// Unlike Music, Spotify exposes artwork as an `https://i.scdn.co/...` URL instead of
/// Apple Event data, and reports track duration in milliseconds.
final class SpotifyPlayer: MediaPlayer {

    let bundleID = "com.spotify.client"
    let displayName = "Spotify"

    var changeNotifications: [Notification.Name] {
        [Notification.Name("com.spotify.client.PlaybackStateChanged")]
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
            // Spotify reports duration in milliseconds.
            let seconds = (Double(fields[4]) ?? 0) / 1000
            let artwork = fields.count >= 8 && !fields[7].isEmpty ? fields[7] : nil
            return .snapshot(
                PlayerSnapshot(
                    state: stateText == "playing" ? .playing : .paused,
                    track: TrackInfo(
                        title: fields[1],
                        artist: fields[2],
                        album: fields[3],
                        duration: seconds,
                        persistentID: fields[6],
                        artworkURL: artwork
                    ),
                    position: Double(fields[5]) ?? 0
                )
            )
        default:
            return .snapshot(PlayerSnapshot(state: .stopped, track: nil, position: 0))
        }
    }

    func artworkData(for track: TrackInfo, timeout: TimeInterval) -> Data? {
        ArtworkFetch.synchronously(track.artworkURL, timeout: timeout)
    }

    func setPlaying(_ playing: Bool) { run(playing ? "play" : "pause") }
    func next() { run("next track") }
    func previous() { run("previous track") }

    func seek(to seconds: Double) {
        run("set player position to \(String(format: "%.2f", seconds))")
    }

    private func run(_ body: String) {
        _ = AppleScriptRunner.run("tell application \"Spotify\" to \(body)", timeout: 4)
    }

    private enum Scripts {
        static let state = """
        tell application "Spotify"
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
                set pid to (id of t)
            end try
            set art to ""
            try
                set art to (artwork url of t)
            end try
            return pstate & sep & nm & sep & ar & sep & al & sep & (du as text) & sep & (ps as text) & sep & pid & sep & art
        end tell
        """
    }
}
