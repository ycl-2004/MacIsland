/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// A countdown anchored to the moment it runs out.
///
/// Taking a second off per tick loses time whenever a tick is late or never
/// fires -- the Mac asleep, the main thread busy -- and the timer then ends
/// late by exactly that much. Reading the time left off the end date cannot
/// drift, and a timer that ran out during sleep is simply over on wake.
struct TimerCountdown {
    /// When the time runs out; nil while paused.
    private var endDate: Date?
    /// The exact time left when paused, so a pause neither gains nor loses
    /// the part of a second it happened in.
    private var timeLeftWhilePaused: TimeInterval

    init(duration: TimeInterval, startingAt now: Date = Date()) {
        endDate = now.addingTimeInterval(duration)
        timeLeftWhilePaused = duration
    }

    func timeLeft(at now: Date = Date()) -> TimeInterval {
        endDate.map { $0.timeIntervalSince(now) } ?? timeLeftWhilePaused
    }

    /// Whole seconds as displayed: rounded up while counting down, so 0:00
    /// shows only once the time is actually up, then whole seconds of
    /// overtime as a negative number.
    func displayedSeconds(at now: Date = Date()) -> TimeInterval {
        let left = timeLeft(at: now)
        if left > 0 { return left.rounded(.up) }
        let overtime = (-left).rounded(.down)
        return overtime == 0 ? 0 : -overtime
    }

    mutating func pause(at now: Date = Date()) {
        guard let endDate else { return }
        timeLeftWhilePaused = endDate.timeIntervalSince(now)
        self.endDate = nil
    }

    mutating func resume(at now: Date = Date()) {
        guard endDate == nil else { return }
        endDate = now.addingTimeInterval(timeLeftWhilePaused)
    }
}
