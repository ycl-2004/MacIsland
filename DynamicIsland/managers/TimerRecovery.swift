import Foundation

struct TimerRecovery: Codable, Sendable {
    struct Active: Codable, Sendable {
        let countdown: TimerCountdown
        let duration: TimeInterval
        let name: String
        let paused: Bool
        let presetID: UUID?

        func isRestorable(at now: Date = Date()) -> Bool {
            let remaining = countdown.timeLeft(at: now)
            return duration.isFinite && duration > 0 && duration <= 366 * 24 * 3600
                && remaining.isFinite && remaining > 0 && remaining <= duration
                && name.utf8.count <= 4096
        }
    }
    let active: Active?
}
