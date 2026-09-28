import Foundation

/// Terminal's tabs report their tty, which is the agent's controlling terminal.
struct AppleTerminalHost: TerminalHost {
    static let id = "com.apple.Terminal"

    let bundleIdentifier = Self.id
    let displayName = "Terminal"
    let paneDiscovery = TerminalPaneDiscovery.controllingTerminal
    let permissionHint = String(localized: "Allow Atoll to control Terminal in System Settings → Privacy & Security → Automation.")

    /// The window and tab using `device`; every script below starts from it.
    private static let findTab = """
        on tabUsing(device)
            tell application id "\(id)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is device then return {contents of w, contents of t}
                    end repeat
                end repeat
            end tell
            error "No Terminal tab uses " & device
        end tabUsing
        """

    func focusCommands(pane: String) -> [TerminalCommand] {
        [TerminalCommand(program: .appleScript(Self.findTab + """

            on run argv
                set {w, t} to tabUsing(item 1 of argv)
                tell application id "\(Self.id)"
                    -- In the background, Terminal defers reordering its windows.
                    activate
                    set selected of t to true
                    set index of w to 1
                end tell
            end run
            """), arguments: [pane])]
    }

    func typeCommands(text: String, pane: String) -> [TerminalCommand] {
        // `do script` types the text as it is, so its line breaks arrive as
        // Ctrl+J, and presses Return right after it. An agent that takes a fast
        // burst of keys as a paste (Codex, since Terminal does not mark pastes)
        // keeps that Return in the message, so Return is pressed again once the
        // burst is over; an agent that already sent it sees an empty prompt.
        [TerminalCommand(program: .appleScript(Self.findTab + """

            on run argv
                set message to read (POSIX file (item 2 of argv)) as «class utf8»
                set {w, t} to tabUsing(item 1 of argv)
                tell application id "\(Self.id)"
                    do script message in t
                    delay 0.3
                    do script "" in t
                end tell
            end run
            """), arguments: [pane], text: TerminalText.printable(text))]
    }
}
