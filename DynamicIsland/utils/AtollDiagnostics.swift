import Foundation
import OSLog

/// Never stores user text, paths, payloads or credentials. Only fixed code sites
/// and bounded counters survive in the diagnostic snapshot.
enum AtollDiagnostics {
    static let subsystem = "com.ebullioscopic.Atoll"
    static let legacySubsystems = [subsystem, "com.Ebullioscopic.Atoll", "com.Ebullioscopic.Atoll.dev", "com.atoll.dynamicisland"]
    static var exportPredicate: String { legacySubsystems.map { "subsystem == '\($0)'" }.joined(separator: " OR ") }
    static let events = DiagnosticEvents()

    /// A support archive remains bounded even after years of crash reports.
    static func copyRecentCrashReports(from directories: [URL], to destination: URL, now: Date = Date()) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var candidates: [(URL, Int, Date)] = []
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
            for file in files where file.lastPathComponent.hasPrefix("Atoll") && ["ips", "crash", "hang"].contains(file.pathExtension) {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                      values.isSymbolicLink != true, let size = values.fileSize, size <= 4 * 1024 * 1024,
                      let date = values.contentModificationDate, now.timeIntervalSince(date) <= 7 * 86400 else { continue }
                candidates.append((file, size, date))
            }
        }
        var bytes = 0
        for (file, size, _) in candidates.sorted(by: { $0.2 > $1.2 }).prefix(8) {
            guard bytes + size <= 16 * 1024 * 1024 else { continue }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try FileManager.default.copyItem(at: file, to: target)
            bytes += size
        }
    }

    static var buildInfo: [String: String] {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode([String: String].self, from: data) else {
            return ["source": "unrecorded", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"]
        }
        return info
    }

    static func snapshotData(states: [String: String] = [:]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "build": buildInfo,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "uptimeSeconds": Int(ProcessInfo.processInfo.systemUptime),
            "states": states,
            "events": events.snapshot()
        ], options: [.prettyPrinted, .sortedKeys])
    }
}

final class DiagnosticEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (last: TimeInterval, count: Int)] = [:]
    private var order: [String] = []
    private let maximum = 128

    /// True only once per site per minute; counters still include suppressed events.
    func record(site: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        lock.withLock {
            if var entry = entries[site] {
                entry.count = min(Int.max - 1, entry.count) + 1
                let emit = now - entry.last >= 60
                if emit { entry.last = now }
                entries[site] = entry
                return emit
            }
            if order.count == maximum { entries.removeValue(forKey: order.removeFirst()) }
            order.append(site)
            entries[site] = (now, 1)
            return true
        }
    }

    func snapshot() -> [[String: Any]] {
        lock.withLock { order.compactMap { site in
            entries[site].map { ["site": site, "count": $0.count, "lastUptime": $0.last] }
        } }
    }
}
