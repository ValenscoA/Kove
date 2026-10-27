import Foundation

struct AppleScriptResult {
    let output: String
    let error: String
    let code: Int32

    var succeeded: Bool { code == 0 }
    var isPermissionDenied: Bool {
        error.contains("-1743") || error.lowercased().contains("not authorized")
    }
}

enum AppleScriptRunner {

    /// Runs `osascript` out of process so a stalled Music.app can never block the UI.
    static func run(_ source: String, timeout: TimeInterval = 5) -> AppleScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return AppleScriptResult(output: "", error: error.localizedDescription, code: -1)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning { process.terminate() }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return AppleScriptResult(
            output: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .newlines),
            error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            code: process.isRunning ? -1 : process.terminationStatus
        )
    }
}

enum MusicScripts {

    /// Field separator (ASCII unit separator) — never appears in track metadata.
    static let separator = "\u{1F}"

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

    static func command(_ body: String) -> String {
        "tell application \"Music\" to \(body)"
    }
}
