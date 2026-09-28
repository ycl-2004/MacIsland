/// Every terminal Atoll can bring back to a session's pane and type into.
enum TerminalHostRegistry {
    static let hosts: [TerminalHost] = [
        CmuxTerminalHost(),
        GhosttyTerminalHost(),
        AppleTerminalHost(),
    ]

    static func host(bundleIdentifier: String?) -> TerminalHost? {
        guard let bundleIdentifier else { return nil }
        return hosts.first { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
    }
}
