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
