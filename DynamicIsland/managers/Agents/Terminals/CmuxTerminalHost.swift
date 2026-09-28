import Foundation

/// cmux names every pane in `CMUX_SURFACE_ID` and takes commands from the
/// `cmux` tool inside its bundle, over its local socket.
struct CmuxTerminalHost: TerminalHost {
    let bundleIdentifier = "com.cmuxterm.app"
    let displayName = "cmux"
    let paneDiscovery = TerminalPaneDiscovery.environment("CMUX_SURFACE_ID")
    let permissionHint = String(localized: "In cmux, open Settings → Automation and allow other apps to control cmux.")

    private static let tool = TerminalCommand.Program.bundledTool("Contents/Resources/bin/cmux")

    func focusCommands(pane: String) -> [TerminalCommand] {
        [TerminalCommand(program: Self.tool, arguments: ["focus-panel", "--panel", pane])]
    }

    func typeCommands(text: String, pane: String) -> [TerminalCommand] {
        // `send` turns a line break into Return, so lines go one by one with
        // Shift+Return between them: cmux reports keys in the kitty keyboard
        // protocol when the agent asks for it, which Claude Code and Codex do,
        // and both take Shift+Return as a new line (a Ctrl+J is dropped there).
        // `--` keeps a line starting with "-" from reading as a flag.
        var commands: [TerminalCommand] = []
        for (index, line) in TerminalText.lines(text).enumerated() {
            if index > 0 { commands.append(key("shift+enter", pane: pane)) }
            for piece in Self.literalPieces(line) {
                commands.append(TerminalCommand(program: Self.tool, arguments: ["send", "--surface", pane, "--"], text: piece))
            }
        }
        return commands + [key("enter", pane: pane)]
    }

    /// `send` reads `\n`, `\r` and `\t` as keys and has no escape for a literal
    /// backslash, so a line is cut after each backslash that starts one of
    /// them; split across two sends, the pair arrives as typed.
    static func literalPieces(_ line: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var characters = line.makeIterator()
        var next = characters.next()
        while let character = next {
            current.append(character)
            next = characters.next()
            if character == "\\", let following = next, "nrt".contains(following) {
                pieces.append(current)
                current = ""
            }
        }
        return current.isEmpty ? pieces : pieces + [current]
    }

    private func key(_ name: String, pane: String) -> TerminalCommand {
        TerminalCommand(program: Self.tool, arguments: ["send-key", "--surface", pane, "--", name])
    }
}
