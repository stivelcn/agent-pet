import Foundation

/// Exact-tab navigation. A successful process exit alone is not enough: the
/// AppleScript must actually find the requested TTY and return true.
enum TerminalFocus {
    static func focusExact(program: String, tty: String) async -> Bool {
        guard let script = script(program: program, tty: tty) else { return false }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            // Bound an unavailable/blocked client instead of leaving osascript behind.
            let deadline = Date().addingTimeInterval(8)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                return false
            }
            process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            return process.terminationStatus == 0 && text?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }.value
    }

    static func script(program: String, tty: String) -> String? {
        // Only actual macOS TTY paths belong in a script, never an arbitrary payload string.
        guard tty.hasPrefix("/dev/tty"), tty.count > 8,
              tty.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "/" }) else { return nil }
        switch program {
        case "Apple_Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (tty of t) is "\(tty)" then
                                set selected of t to true
                                set frontmost of w to true
                                activate
                                return true
                            end if
                        end try
                    end repeat
                end repeat
                return false
            end tell
            """
        case "iTerm.app":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if (tty of s) is "\(tty)" then
                                    select w
                                    select t
                                    select s
                                    activate
                                    return true
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
                return false
            end tell
            """
        default: return nil
        }
    }
}
