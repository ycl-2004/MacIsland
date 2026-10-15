import Foundation

/// Reset the budget only after a genuinely stable connection, not a child that
/// briefly starts and immediately dies. This prevents infinite crash loops.
struct ServiceRetryPolicy {
    private(set) var failures = 0
    private var readyAt: TimeInterval?
    var maximumRetries = 6
    var baseDelay: TimeInterval = 1
    var stableInterval: TimeInterval = 60

    mutating func ready(now: TimeInterval = ProcessInfo.processInfo.systemUptime) { readyAt = now }
    /// A new bounded round, for a fresh start the user or the system asked for.
    mutating func reset() { failures = 0; readyAt = nil }
    mutating func nextDelay(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
        if let readyAt, now - readyAt >= stableInterval { failures = 0 }
        readyAt = nil
        guard failures < maximumRetries else { return nil }
        let delay = min(30, baseDelay * pow(2, Double(failures)))
        failures += 1
        return delay
    }
}
