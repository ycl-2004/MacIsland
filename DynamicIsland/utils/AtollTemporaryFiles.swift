import Foundation

/// Shelf attachments outlive a run. Other temporary files belong to one app
/// instance, so a retiring instance never removes its replacement's files.
enum AtollTemporaryFiles {
    enum Area: String, CaseIterable {
        /// Screenshots taken for a screen question.
        case screenQuestion = "ScreenQuestion"
        /// Messages on their way into a terminal.
        case terminalText = "TerminalText"
        /// Files the shelf made from dropped data. Saved shelf items can still
        /// use them after a relaunch, so the shelf removes its own leftovers.
        case shelf = "Shelf"
        /// Logs gathered for an export.
        case logs = "Logs"
    }

    static let root = AppRuntimeEnvironment.contentURL(FileManager.default.temporaryDirectory.appendingPathComponent("Atoll", isDirectory: true), testPath: "Temporary")
    private static let runDirectory = root.appendingPathComponent("Runs/\(ProcessInfo.processInfo.processIdentifier)-\(UUID())", isDirectory: true)

    private static func path(_ area: Area) -> URL {
        (area == .shelf ? root : runDirectory).appendingPathComponent(area.rawValue, isDirectory: true)
    }

    /// The folder for one feature's temporary files, created when missing and
    /// readable by this user only.
    static func directory(_ area: Area) -> URL {
        let url = path(area)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Removes every area's files except those in `kept`, and what earlier
    /// versions left directly in the temporary folder.
    static func removeAll(except kept: Set<Area>) {
        let fm = FileManager.default
        for area in Area.allCases where !kept.contains(area) {
            try? fm.removeItem(at: path(area))
        }
        rmdir(runDirectory.path)
        removeDeadRuns()
        removeLegacyFiles()
    }

    private static func removeDeadRuns() {
        let fm = FileManager.default
        let folder = root.appendingPathComponent("Runs", isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true,
                  let prefix = entry.lastPathComponent.split(separator: "-").first,
                  let pid = Int32(prefix), pid > 1, kill(pid, 0) == -1, errno == ESRCH else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    /// How old an entry has to be before `removeUnused` may take it. What is in
    /// use is decided before the sweep runs, so a file written a moment ago --
    /// a drop still on its way to becoming an item -- would otherwise look unused.
    static let unusedEntryMinimumAge: TimeInterval = 60

    /// Removes the entries of `area` that are not among `inUse` and older than
    /// `unusedEntryMinimumAge`, then the area's folder and the root once
    /// nothing is left in them.
    static func removeUnused(in area: Area, inUse: Set<URL>) {
        let folder = path(area)
        removeEntries(of: folder, notIn: inUse, createdBefore: Date().addingTimeInterval(-unusedEntryMinimumAge))
        // `rmdir` only removes an empty folder, so one a new file has just gone
        // into stays.
        rmdir(folder.path)
        rmdir(root.path)
    }

    /// Removes each entry of `folder` that neither is nor contains a file in
    /// `inUse`, sparing entries created at or after `cutoff`.
    static func removeEntries(of folder: URL, notIn inUse: Set<URL>, createdBefore cutoff: Date = .distantFuture) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        // Bookmarks resolve to /private/var/…, the temporary folder reads /var/…
        let keep = Set(inUse.map { $0.resolvingSymlinksInPath().path })
        for entry in entries {
            let path = entry.resolvingSymlinksInPath().path
            guard !keep.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) else { continue }
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard created < cutoff else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    /// Names earlier versions wrote straight into the temporary folder.
    private static let legacyPrefixes = ["atoll_artwork_wallpaper_", "atoll-screen-question-", "AtollScreenQuestion", "AtollTerminalText"]

    private static func removeLegacyFiles() {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: temporary.path) else { return }
        for name in names where legacyPrefixes.contains(where: name.hasPrefix) {
            let url = temporary.appendingPathComponent(name)
            // An older application version might still be alive during upgrade.
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified < Date().addingTimeInterval(-86400) else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
