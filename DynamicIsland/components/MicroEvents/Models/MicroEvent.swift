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

/// How often a Micro Event comes back. Deliberately limited to these four:
/// a rule the user can read at a glance is more useful here than an RRULE.
enum MicroEventRecurrence: String, Codable, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .once: return String(localized: "Once")
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        }
    }
}

/// One thing the user wants to be reminded of, and how often.
///
/// The repeat rule is stored as plain components rather than a `Date` for every
/// future occurrence: one date rolls over daylight saving and month lengths
/// differently from another, so the next occurrence is always derived from the
/// rule at the moment it is needed.
struct MicroEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var recurrence: MicroEventRecurrence
    /// Local wall-clock time the item is due.
    var hour: Int
    var minute: Int
    /// `Calendar` weekday numbers (1 = Sunday) for `.weekly`.
    var weekdays: Set<Int>
    /// Day of the month for `.monthly`, clamped to the length of each month.
    var dayOfMonth: Int
    /// The exact moment for `.once`; the earliest day a repeating rule may fire.
    var startDate: Date
    var isEnabled: Bool
    /// Occurrence keys already ticked off, oldest first.
    var completedKeys: [String]
    /// When a one-off was checked, so midnight cleanup follows completion day.
    /// Optional for compatibility with lists saved before this field existed.
    var completedAt: Date? = nil
    var createdAt: Date

    /// Bounded so a daily item does not grow its history forever.
    static let completedKeyLimit = 60

    init(
        id: UUID = UUID(),
        title: String,
        recurrence: MicroEventRecurrence = .daily,
        hour: Int = 9,
        minute: Int = 0,
        weekdays: Set<Int> = [],
        dayOfMonth: Int = 1,
        startDate: Date = Date(),
        isEnabled: Bool = true,
        completedKeys: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.recurrence = recurrence
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.isEnabled = isEnabled
        self.completedKeys = completedKeys
        self.createdAt = createdAt
    }

    // MARK: - Editing

    /// Applies the range rules once, at the edge, so the rest of the feature can
    /// assume a usable rule.
    func normalized(calendar: Calendar = .autoupdatingCurrent) -> MicroEvent {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.hour = min(max(hour, 0), 23)
        copy.minute = min(max(minute, 0), 59)
        copy.dayOfMonth = min(max(dayOfMonth, 1), 31)
        copy.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        if copy.recurrence == .weekly && copy.weekdays.isEmpty {
            copy.weekdays = [calendar.component(.weekday, from: copy.startDate)]
        }
        if copy.recurrence == .once {
            copy.weekdays = []
        } else {
            copy.completedAt = nil
        }
        copy.completedKeys = Array(completedKeys.suffix(Self.completedKeyLimit))
        return copy
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (recurrence != .weekly || !weekdays.isEmpty)
    }

    /// The editor's working copy of a stored item: a one-off shows the time it
    /// was saved with.
    func preparedForEditing(calendar: Calendar = .autoupdatingCurrent) -> MicroEvent {
        guard recurrence == .once else { return self }
        var copy = self
        copy.hour = calendar.component(.hour, from: startDate)
        copy.minute = calendar.component(.minute, from: startDate)
        return copy
    }

    /// What an editor saves, or nil when the draft cannot be saved yet. Both
    /// editors go through here so the rules exist once.
    ///
    /// `original` is the stored item being replaced, nil for a new one.
    func preparedForSaving(replacing original: MicroEvent?, now: Date = Date(),
                           calendar: Calendar = .autoupdatingCurrent) -> MicroEvent? {
        guard isValid else { return nil }
        var value = normalized(calendar: calendar)
        if value.recurrence == .once {
            guard let date = value.onceDate(calendar: calendar), date > now else { return nil }
            if let original, original.recurrence != .once || original.startDate != date {
                value.completedKeys.removeAll { $0 == Self.onceKey }
                value.completedAt = nil
            }
            value.startDate = date
        } else {
            value.completedKeys.removeAll { $0 == Self.onceKey }
            // A repeating rule has no start date in the editor. One inherited
            // from a one-off would silence the rule until that day.
            if original?.recurrence == .once || value.startDate > now {
                value.startDate = calendar.startOfDay(for: now)
            }
        }
        return value
    }

    var timeDescription: String {
        let components = DateComponents(hour: hour, minute: minute)
        let calendar = Calendar.autoupdatingCurrent
        guard let date = calendar.date(from: components) else { return "" }
        return Self.timeFormatter.string(from: date)
    }

    /// "Daily · 9:00 AM", "Mon, Wed · 7:30 PM", "Mar 3 · 9:00 AM".
    var scheduleDescription: String {
        switch recurrence {
        case .once:
            return "\(String(localized: "Once")) · \(startDate.formatted(date: .abbreviated, time: .shortened))"
        case .daily:
            return "\(String(localized: "Daily")) · \(timeDescription)"
        case .weekly:
            let names = Self.orderedWeekdays
                .filter { weekdays.contains($0) }
                .map { Calendar.autoupdatingCurrent.shortStandaloneWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
            return "\(String(localized: "Weekly")) · \(names) · \(timeDescription)"
        case .monthly:
            return "\(String(localized: "Monthly")) · \(String(format: String(localized: "Day %lld"), dayOfMonth)) · \(timeDescription)"
        }
    }

    // MARK: - Occurrences

    /// The selected day and typed time together define a one-off occurrence.
    func onceDate(calendar: Calendar = .autoupdatingCurrent) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startDate,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    /// The first occurrence strictly after `reference`.
    ///
    /// Day-by-day search rather than `nextDate(after:matching:)`: the monthly
    /// rule has to clamp 31 to the length of a short month, and a missing
    /// wall-clock time on a daylight-saving day has to land on that day rather
    /// than skip a month.
    func nextOccurrence(after reference: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        switch recurrence {
        case .once:
            return startDate > reference ? startDate : nil
        case .daily, .weekly, .monthly:
            let firstDay = calendar.startOfDay(for: reference)
            for offset in 0...Self.searchHorizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                      let candidate = time(on: day, calendar: calendar),
                      candidate > reference,
                      candidate >= startDate,
                      matches(candidate, calendar: calendar) else { continue }
                return candidate
            }
            return nil
        }
    }

    /// The occurrence on the same day as `reference`, if the rule covers that
    /// day. This is what a list row ticks off, so an item due at 18:00 can be
    /// completed at 09:00.
    func occurrence(onDayOf reference: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let day = calendar.startOfDay(for: reference)
        switch recurrence {
        case .once:
            return calendar.isDate(startDate, inSameDayAs: day) ? startDate : nil
        case .daily, .weekly, .monthly:
            guard let candidate = time(on: day, calendar: calendar),
                  candidate >= startDate,
                  matches(candidate, calendar: calendar) else { return nil }
            return candidate
        }
    }

    /// What the row is about now: today's occurrence when the rule covers today,
    /// otherwise the next one.
    func currentOrNextOccurrence(from reference: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        occurrence(onDayOf: reference, calendar: calendar)
            ?? nextOccurrence(after: reference, calendar: calendar)
    }

    // MARK: - Completion

    func occurrenceKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard recurrence != .once else { return Self.onceKey }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func isCompleted(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        completedKeys.contains(occurrenceKey(for: date, calendar: calendar))
    }

    func markingCompleted(_ date: Date, calendar: Calendar = .autoupdatingCurrent,
                          completedAt: Date = Date()) -> MicroEvent {
        var copy = self
        let key = occurrenceKey(for: date, calendar: calendar)
        if !copy.completedKeys.contains(key) {
            copy.completedKeys.append(key)
            if recurrence == .once { copy.completedAt = completedAt }
        }
        copy.completedKeys = Array(copy.completedKeys.suffix(Self.completedKeyLimit))
        return copy
    }

    func clearingCompletion(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> MicroEvent {
        var copy = self
        copy.completedKeys.removeAll { $0 == occurrenceKey(for: date, calendar: calendar) }
        if recurrence == .once { copy.completedAt = nil }
        return copy
    }

    // MARK: - Private

    static let onceKey = "once"
    private static let searchHorizonDays = 400
    /// Monday first, which is how the weekday chips read.
    static let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func weekdaySymbol(for weekday: Int) -> String {
        let symbols = Calendar.autoupdatingCurrent.veryShortStandaloneWeekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    private func time(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0,
                      of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                      direction: .forward)
    }

    private func matches(_ date: Date, calendar: Calendar) -> Bool {
        switch recurrence {
        case .once:
            return true
        case .daily:
            return true
        case .weekly:
            return weekdays.contains(calendar.component(.weekday, from: date))
        case .monthly:
            let day = calendar.component(.day, from: date)
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            return day == min(dayOfMonth, daysInMonth)
        }
    }
}

extension MicroEvent {
    /// Relative wording for the row's trailing label: "in 2h", "tomorrow",
    /// "now". Kept short because the row is narrow.
    static func relativeDescription(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return String(localized: "now") }
        if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return String(format: String(localized: "in %lld min"), minutes)
        }
        if calendar.isDateInToday(date) {
            return String(format: String(localized: "in %lld h"), Int(seconds / 3600))
        }
        if calendar.isDateInTomorrow(date) { return String(localized: "tomorrow") }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days > 0 && days < 7 {
            return String(format: String(localized: "in %lld d"), days)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
