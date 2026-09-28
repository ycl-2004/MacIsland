import Foundation

/// One program run against a terminal app: AppleScript through `osascript`,
/// or a command-line tool the app ships inside its bundle.
struct TerminalCommand: Equatable {
    enum Program: Equatable {
        /// Script source. Its `run` handler receives `arguments` as `argv`, so
        /// nothing it is given becomes part of the script. With `text`, the
        /// last `argv` item is the path of a UTF-8 file holding it.
        case appleScript(String)
        /// A tool at this path inside the terminal's app bundle. With `text`,
        /// the text is its last argument.
        case bundledTool(String)
    }

    let program: Program
    let arguments: [String]
    /// What the user typed. It travels through a file rather than as an
    /// argument, which `Process` would decompose (ä → a + ¨, 한 → ᄒ ᅡ ᆫ).
    var text: String? = nil
}

/// How Atoll learns which pane of a terminal a session runs in.
enum TerminalPaneDiscovery: Equatable {
    /// Every pane names itself in this environment variable, which the hook forwards (cmux).
    case environment(String)
    /// The pane is the agent's controlling terminal device (Terminal's tabs report their tty).
    case controllingTerminal
    /// The terminal names its panes nowhere a hook can see, so Atoll asks for
    /// the focused pane right after the user acts in the session (Ghostty).
    /// The query prints the pane and its working directory on two lines; the
    /// answer counts only when that directory is the session's.
    case focusedPane(query: TerminalCommand)
}

/// A terminal app in which Atoll can bring back a session's own pane and type
/// into it, exactly as the user would.
///
/// A host only declares what is specific to its app: how its panes are found
/// and which commands focus or type into one. Running those commands, checking
/// that the agent still owns the pane, and framing text as one paste are shared
/// in `AgentTerminals`, so a new terminal is one small type plus one line in
/// `TerminalHostRegistry`.
protocol TerminalHost {
    var bundleIdentifier: String { get }
    var displayName: String { get }
    var paneDiscovery: TerminalPaneDiscovery { get }
    /// What to change when the terminal refuses Atoll's commands.
    var permissionHint: String { get }
    /// Brings the pane to the front of its window.
    func focusCommands(pane: String) -> [TerminalCommand]
    /// Types `text` into the pane and presses Return, so the agent takes it as
    /// one message: each line break goes in the way the agent's prompt takes
    /// as a new line rather than as sending.
    func typeCommands(text: String, pane: String) -> [TerminalCommand]
}

enum TerminalText {
    /// The message's lines, with control characters dropped so the text cannot
    /// act as keys (Escape, Return, Ctrl+C) in the agent's prompt.
    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(String.UnicodeScalarView(line.unicodeScalars.filter {
                    $0 == "\t" || $0.properties.generalCategory != .control
                }))
            }
    }

    /// The lines joined by `\n`: pasted, a new line; typed, the byte Ctrl+J
    /// sends, which an agent's prompt also takes as a new line.
    static func printable(_ text: String) -> String {
        lines(text).joined(separator: "\n")
    }
}
