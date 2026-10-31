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

import AppKit
import AVFoundation
import Combine
import Defaults
import Foundation
import os

/// Delivers Micro Events through Atoll's own surfaces only.
///
/// No `UNUserNotificationCenter`: a system notification needs an entitlement to
/// break through Focus, and this feature deliberately does not ask for one. The
/// closed-notch peek and Atoll's own audio are not filtered by Focus at all, and
/// if the app is not running there is simply no reminder.
///
/// Tasks sleep until the next delivery, due-state change and day boundary.
/// Nothing polls.
@MainActor
final class MicroEventManager: ObservableObject {
    static let shared = MicroEventManager()

    /// How late a missed item may still be delivered (for example after a short
    /// sleep). Anything older is not replayed.
    static let lateDeliveryWindow: TimeInterval = 120

    @Published private(set) var refreshToken = UUID()
    @Published private(set) var nextFireDate: Date?

    private let store: MicroEventStore
    private let calendar: Calendar
    private let logger = os.Logger(subsystem: AtollDiagnostics.subsystem, category: "MicroEvents")

    private var cancellables = Set<AnyCancellable>()
    private var deliveryTask: Task<Void, Never>?
    private var dayBoundaryTask: Task<Void, Never>?
    private var dueStateTask: Task<Void, Never>?
    private var soundPlayer: AVAudioPlayer?
    /// "id|occurrenceKey", kept for this launch only, so a reschedule cannot
    /// deliver the same occurrence twice.
    private var deliveredKeys: Set<String> = []

    private init() {
        self.store = .shared
        self.calendar = .autoupdatingCurrent
        observeStore()
        observeDefaults()
        observeSystem()
    }

    // MARK: - Demand gate

    var isEnabled: Bool { Defaults[.enableMicroEventsFeature] }

    /// Number of enabled items whose occurrence today is not ticked off yet.
    /// Computed rather than stored so a midnight rollover cannot leave a stale
    /// badge behind; `refreshToken` tells SwiftUI when to ask again.
    func dueTodayCount(now: Date = Date()) -> Int {
        guard isEnabled else { return 0 }
        return store.events.reduce(into: 0) { count, event in
            guard event.isEnabled,
                  let occurrence = event.occurrence(onDayOf: now, calendar: calendar),
                  !event.isCompleted(occurrence, calendar: calendar) else { return }
            count += 1
        }
    }

    // MARK: - Scheduling

    func reschedule(now: Date = Date()) {
        deliveryTask?.cancel()
        dayBoundaryTask?.cancel()
        dueStateTask?.cancel()
        deliveryTask = nil
        dayBoundaryTask = nil
        dueStateTask = nil
        nextFireDate = nil
        refreshToken = UUID()

        guard isEnabled else { return }
        store.loadIfNeeded()
        store.cleanupExpiredOccurrences(now: now, calendar: calendar)

        let lead = TimeInterval(max(0, Defaults[.microEventsLeadMinutes]) * 60)
        // An early reminder fires before the item becomes overdue. Refresh once
        // at its actual due time even while the notch stays open.
        if lead > 0, let due = Self.nextDueStateChange(events: store.events, now: now, calendar: calendar) {
            let delay = max(0, due.timeIntervalSince(now))
            dueStateTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.reschedule()
            }
        }
        let next = store.events
            .filter(\.isEnabled)
            .compactMap { event -> (event: MicroEvent, occurrence: Date, delivery: Date)? in
                guard let match = Self.nextDelivery(for: event, now: now, lead: lead,
                                                    deliveredKeys: deliveredKeys, calendar: calendar) else { return nil }
                return (event, match.occurrence, match.delivery)
            }
            .min { $0.delivery < $1.delivery }

        guard let next else {
            scheduleDayBoundary(now: now)
            return
        }

        nextFireDate = next.delivery
        let delay = max(0, next.delivery.timeIntervalSince(now))
        logger.debug("Next Micro Event in \(Int(delay), privacy: .public)s")
        deliveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.deliver(eventID: next.event.id, occurrence: next.occurrence)
        }
        scheduleDayBoundary(now: now)
    }

    static func nextDueStateChange(events: [MicroEvent], now: Date,
                                   calendar: Calendar = .autoupdatingCurrent) -> Date? {
        events.filter(\.isEnabled).compactMap { event in
            guard let occurrence = event.nextOccurrence(after: now, calendar: calendar),
                  !event.isCompleted(occurrence, calendar: calendar) else { return nil }
            return occurrence
        }.min()
    }

    /// The first delivery that is neither already delivered in this launch nor
    /// so old that replaying it would be noise.
    static func nextDelivery(
        for event: MicroEvent,
        now: Date,
        lead: TimeInterval,
        deliveredKeys: Set<String> = [],
        calendar: Calendar = .autoupdatingCurrent
    ) -> (occurrence: Date, delivery: Date)? {
        let earliest = now.addingTimeInterval(-Self.lateDeliveryWindow + lead)
        var reference = earliest
        for _ in 0..<(MicroEvent.completedKeyLimit + deliveredKeys.count + 2) {
            guard let occurrence = event.nextOccurrence(after: reference, calendar: calendar) else {
                return nil
            }
            let delivery = occurrence.addingTimeInterval(-lead)
            let key = deliveryKey(eventID: event.id, occurrence: occurrence)
            if event.isCompleted(occurrence, calendar: calendar)
                || deliveredKeys.contains(key) || delivery < now.addingTimeInterval(-Self.lateDeliveryWindow) {
                reference = occurrence
                continue
            }
            return (occurrence, delivery)
        }
        return nil
    }

    /// Recomputes the "today" badge when the date changes, even if no item is
    /// due. One task per day, not a ticker.
    private func scheduleDayBoundary(now: Date) {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return
        }
        let delay = max(1, tomorrow.timeIntervalSince(now) + 1)
        dayBoundaryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.reschedule()
        }
    }

    // MARK: - Delivery

    private func deliver(eventID: UUID, occurrence: Date) {
        guard isEnabled else {
            reschedule()
            return
        }
        guard let event = store.events.first(where: { $0.id == eventID }),
              event.isEnabled,
              !event.isCompleted(occurrence, calendar: calendar),
              occurrence.timeIntervalSinceNow > -Self.lateDeliveryWindow
        else {
            reschedule()
            return
        }

        deliveredKeys.insert(Self.deliveryKey(eventID: event.id, occurrence: occurrence))
        if deliveredKeys.count > 200 {
            deliveredKeys.removeAll()
        }
        logger.log("Delivering Micro Event \(event.id.uuidString, privacy: .public)")

        if Defaults[.microEventsPlaySound] {
            playChime()
        }

        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .microEvent,
            duration: 8,
            icon: "checklist",
            title: event.title,
            subtitle: event.scheduleDescription
        )
        refreshToken = UUID()
        reschedule()
    }

    private static func deliveryKey(eventID: UUID, occurrence: Date) -> String {
        "\(eventID.uuidString)|\(occurrence.timeIntervalSince1970)"
    }

    private func playChime() {
        guard let url = Bundle.main.url(forResource: TimerSoundStore.bundledSoundFileName, withExtension: nil) else {
            NSSound.beep()
            return
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            NSSound.beep()
            return
        }
        soundPlayer = player
        player.play()
    }

    // MARK: - Observers

    private func observeStore() {
        store.$events
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.reschedule()
            }
            .store(in: &cancellables)
    }

    private func observeDefaults() {
        Defaults.publisher(.enableMicroEventsFeature, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.reschedule()
                } else {
                    self.deliveryTask?.cancel()
                    self.deliveryTask = nil
                    self.dayBoundaryTask?.cancel()
                    self.dayBoundaryTask = nil
                    self.dueStateTask?.cancel()
                    self.dueStateTask = nil
                    self.nextFireDate = nil
                    self.refreshToken = UUID()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.microEventsLeadMinutes, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.reschedule()
            }
            .store(in: &cancellables)

        // An item may have been ticked off with the notch closed.
        store.$isLoaded
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.refreshToken = UUID()
            }
            .store(in: &cancellables)
    }

    private func observeSystem() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
    }
}
