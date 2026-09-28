import Foundation

/// Ghostty's scripting (1.3+) gives every terminal a stable id, but no pane's
/// id reaches its environment, so a session's pane is the one focused when the
/// user acts in it.
struct GhosttyTerminalHost: TerminalHost {
    static let id = "com.mitchellh.ghostty"

    let bundleIdentifier = Self.id
    let displayName = "Ghostty"
    let paneDiscovery = TerminalPaneDiscovery.focusedPane(query: TerminalCommand(program: .appleScript("""
        tell application id "\(Self.id)"
            set t to focused terminal of selected tab of front window
            return (id of t) & linefeed & (working directory of t)
        end tell
        """), arguments: []))
    let permissionHint = String(localized: "Allow Atoll to control Ghostty in System Settings → Privacy & Security → Automation.")

    func focusCommands(pane: String) -> [TerminalCommand] {
        [TerminalCommand(program: .appleScript("""
            on run argv
                tell application id "\(Self.id)" to focus terminal id (item 1 of argv)
            end run
            """), arguments: [pane])]
    }

    func typeCommands(text: String, pane: String) -> [TerminalCommand] {
        // `input text` pastes, the way Ghostty pastes for the program that runs
        // there (bracketed when it asked for that).
        [TerminalCommand(program: .appleScript("""
            on run argv
                set message to read (POSIX file (item 2 of argv)) as «class utf8»
                tell application id "\(Self.id)"
                    set t to terminal id (item 1 of argv)
                    input text message to t
                    send key "enter" to t
                end tell
            end run
            """), arguments: [pane], text: TerminalText.printable(text))]
    }
}
