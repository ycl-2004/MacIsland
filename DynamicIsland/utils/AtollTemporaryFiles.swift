import Foundation

/// Every temporary file Atoll writes lives under one folder, one subfolder per
/// feature, so all of it can be removed together: a launch starts with nothing
/// left from an earlier run, and quitting leaves nothing behind.
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

    /// The folder for one feature's temporary files, created when missing and
    /// readable by this user only.
    static func directory(_ area: Area) -> URL {
        let url = root.appendingPathComponent(area.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }

    /// Removes every area's files except those in `kept`, and what earlier
    /// versions left directly in the temporary folder.
    static func removeAll(except kept: Set<Area>) {
        let fm = FileManager.default
        for area in Area.allCases where !kept.contains(area) {
            try? fm.removeItem(at: root.appendingPathComponent(area.rawValue, isDirectory: true))
        }
        removeLegacyFiles()
    }

    /// How old an entry has to be before `removeUnused` may take it. What is in
    /// use is decided before the sweep runs, so a file written a moment ago --
    /// a drop still on its way to becoming an item -- would otherwise look unused.
    static let unusedEntryMinimumAge: TimeInterval = 60

    /// Removes the entries of `area` that are not among `inUse` and older than
    /// `unusedEntryMinimumAge`, then the area's folder and the root once
    /// nothing is left in them.
    static func removeUnused(in area: Area, inUse: Set<URL>) {
        let folder = root.appendingPathComponent(area.rawValue, isDirectory: true)
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
            try? fm.removeItem(at: temporary.appendingPathComponent(name))
        }
    }
}
