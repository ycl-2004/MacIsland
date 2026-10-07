/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Defaults
import Combine
import EventKit
import SwiftUI

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published private(set) var reminderEvents: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var lockScreenEvents: [EventModel] = []

    private var lockScreenPreviewEvents: [EventModel]?

    private var selectedCalendars: [CalendarModel] = []
    private let calendarService: any CalendarServiceProviding
    private var runtimePolicy = AtollRuntimePolicy()
    private(set) var queryDemand = CalendarQueryDemand()
    private var runtimeCancellables = Set<AnyCancellable>()
    private var needsCalendarReload = true
    private let refreshInterval: TimeInterval
    private var lastEventsFetchDate: Date?
    private var lastReminderEventsFetchDate: Date?
    private var reminderSnapshotDay: Date?
    private let reloadRefreshInterval: TimeInterval = 15
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var pendingEventStoreRefreshTask: Task<Void, Never>?
    private var nextAllowedEventStoreRefresh: Date = .distantPast
    private var ignoreEventStoreChangesUntil: Date = .distantPast
    private let eventStoreChangeThrottle: TimeInterval = 20
    private let selfInducedChangeSuppression: TimeInterval = 6
    private let eventFetchLimiter = EventFetchLimiter()
    private var lastLockScreenEventsFetchDate: Date?
    private let lockScreenRefreshInterval: TimeInterval = 15
    private var lockScreenRefreshTask: Task<Void, Never>?

    var hasCalendarAccess: Bool { isAuthorized(calendarAuthorizationStatus) }
    var hasReminderAccess: Bool { isAuthorized(reminderAuthorizationStatus) }

    init(service: any CalendarServiceProviding = CalendarService(), observeRuntime: Bool = true,
         refreshInterval: TimeInterval = 60) {
        calendarService = service
        self.refreshInterval = refreshInterval
        currentWeekStartDate = CalendarManager.startOfDay(Date())
        guard observeRuntime, !AppRuntimeEnvironment.isTesting else { return }
        refreshAuthorizationSnapshot()
        setupEventStoreChangedObserver()
        RuntimePolicyMonitor.shared.$state.removeDuplicates().sink { [weak self] policy in
            MainActor.assumeIsolated { self?.applyRuntimePolicy(policy) }
        }.store(in: &runtimeCancellables)
        Publishers.MergeMany(
            Defaults.publisher(.enableReminderLiveActivity).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableLockScreenWeatherWidget).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenShowCalendarEvent).map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applyRuntimePolicy(self.runtimePolicy)
            }
        }.store(in: &runtimeCancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshAuthorizationSnapshot()
                    self.applyRuntimePolicy(self.runtimePolicy)
                }
            }.store(in: &runtimeCancellables)
    }

    /// Reads existing authorization only; permission requests stay in explicit settings actions.
    func refreshAuthorizationSnapshot() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func applyRuntimePolicy(_ policy: AtollRuntimePolicy) {
        setQueryDemand(policy: policy, remindersEnabled: Defaults[.enableReminderLiveActivity],
                       lockScreenEnabled: Defaults[.enableLockScreenWeatherWidget] && Defaults[.lockScreenShowCalendarEvent])
    }

    func setQueryDemand(policy: AtollRuntimePolicy, remindersEnabled: Bool, lockScreenEnabled: Bool) {
        let next = CalendarQueryDemand(policy: policy, remindersEnabled: remindersEnabled,
                                       lockScreenEnabled: lockScreenEnabled, hasAccess: hasCalendarAccess || hasReminderAccess)
        let changed = next != queryDemand || policy.isLowPower != runtimePolicy.isLowPower
        runtimePolicy = policy
        queryDemand = next
        guard changed else { return }
        lockScreenRefreshTask?.cancel()
        lockScreenRefreshTask = nil
        if !next.isActive {
            pendingEventStoreRefreshTask?.cancel()
            pendingEventStoreRefreshTask = nil
            return
        }
        startLockScreenRefreshLoop()
    }

    func refreshForCurrentDemand() async {
        guard queryDemand.isActive, !Task.isCancelled else { return }
        if needsCalendarReload { await reloadCalendarAndReminderLists() }
        guard !Task.isCancelled else { return }
        if queryDemand.dayEvents && runtimePolicy.calendarVisible && !runtimePolicy.isLocked { await updateEvents() }
        if queryDemand.reminderEvents { await refreshReminderEvents() }
        if queryDemand.lockScreenEvents { await updateLockScreenEvents() }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pendingEventStoreRefreshTask?.cancel()
        lockScreenRefreshTask?.cancel()
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEventStoreChanged()
        }
    }

    private func handleEventStoreChanged() {
        Logger.log("CalendarManager: Event store changed notification received", category: .lifecycle)
        needsCalendarReload = true
        guard queryDemand.isActive else { return }
        let now = Date()
        guard now >= ignoreEventStoreChangesUntil else { return }

        if now < nextAllowedEventStoreRefresh {
            let delay = max(nextAllowedEventStoreRefresh.timeIntervalSince(now), 0.05)
            scheduleEventStoreRefresh(after: delay)
            return
        }

        nextAllowedEventStoreRefresh = now.addingTimeInterval(eventStoreChangeThrottle)
        scheduleEventStoreRefresh(after: 0)
    }

    private func scheduleEventStoreRefresh(after delay: TimeInterval) {
        pendingEventStoreRefreshTask?.cancel()
        pendingEventStoreRefreshTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled, self.queryDemand.isActive else { return }
            await self.performEventStoreRefresh()
        }
    }

    @MainActor
    private func performEventStoreRefresh() async {
        pendingEventStoreRefreshTask = nil
        await reloadCalendarAndReminderLists()
        if queryDemand.dayEvents && runtimePolicy.calendarVisible && !runtimePolicy.isLocked { await maybeRefreshEventsAfterReload() }
        if queryDemand.reminderEvents { await refreshReminderEvents(force: true) }
        if queryDemand.lockScreenEvents { await updateLockScreenEvents(force: true) }
        nextAllowedEventStoreRefresh = Date().addingTimeInterval(eventStoreChangeThrottle)
        ignoreEventStoreChangesUntil = Date().addingTimeInterval(selfInducedChangeSuppression)
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        let allCalendars = await calendarService.calendars()
        guard !Task.isCancelled else { return }
        needsCalendarReload = false
        eventCalendars = allCalendars.filter { !$0.isReminder }
        reminderLists = allCalendars.filter { $0.isReminder }
        self.allCalendars = allCalendars
        updateSelectedCalendars()
    }

    @MainActor
    private func maybeRefreshEventsAfterReload() async {
        guard hasCalendarAccess || hasReminderAccess else { return }
        let now = Date()
        if let lastFetch = lastEventsFetchDate, now.timeIntervalSince(lastFetch) < reloadRefreshInterval {
            return
        }
        await updateEvents()
    }

    private func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuthorizationStatus = status
        applyRuntimePolicy(runtimePolicy)

        switch status {
        case .notDetermined:
            let granted = await calendarService.requestAccess(to: .event)
            calendarAuthorizationStatus = granted ? .fullAccess : .denied
            applyRuntimePolicy(runtimePolicy)
            if granted {
                await reloadCalendarAndReminderLists()
                await updateEvents(force: true)
                await updateLockScreenEvents(force: true)
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .authorized, .fullAccess:
            await reloadCalendarAndReminderLists()
            await updateEvents(force: true)
            await updateLockScreenEvents(force: true)
        case .writeOnly:
            NSLog("Calendar write only")
        @unknown default:
            NSLog("Unknown calendar authorization status")
        }
    }

    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        reminderAuthorizationStatus = status
        applyRuntimePolicy(runtimePolicy)

        switch status {
        case .notDetermined:
            let granted = await calendarService.requestAccess(to: .reminder)
            reminderAuthorizationStatus = granted ? .fullAccess : .denied
            applyRuntimePolicy(runtimePolicy)
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .authorized, .fullAccess:
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Reminder write only")
        @unknown default:
            NSLog("Unknown reminder authorization status")
        }
    }

    func updateSelectedCalendars() {
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }
        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            if identifiers.isEmpty || identifiers.count == allCalendars.count {
                selectionState = .all
            } else {
                selectionState = .selected(identifiers)
            }
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents(force: true)
        await refreshReminderEvents(force: true)
        await updateLockScreenEvents(force: true)
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await updateEvents(force: true)
        await updateLockScreenEvents(force: true)
    }

    func updateLockScreenEvents(force: Bool = false) async {
        if let previewEvents = lockScreenPreviewEvents {
            if lockScreenEvents != previewEvents {
                withAnimation(.smooth(duration: 0.25)) {
                    lockScreenEvents = previewEvents
                }
            }
            lastLockScreenEventsFetchDate = Date()
            return
        }

        guard queryDemand.lockScreenEvents, !Task.isCancelled else { return }
        let now = Date()

        if !force,
           let lastFetch = lastLockScreenEventsFetchDate,
           now.timeIntervalSince(lastFetch) < lockScreenRefreshInterval {
            return
        }

        let lookaheadRaw = Defaults[.lockScreenCalendarEventLookaheadWindow]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let isAllTimeLookahead =
            lookaheadRaw == "all_time" ||
            lookaheadRaw == "all time" ||
            lookaheadRaw == "alltime"

        let isRestOfDay =
            lookaheadRaw == "rest_of_day" ||
            lookaheadRaw == "rest of the day" ||
            lookaheadRaw == "restofday"

        func lookaheadMinutes(from raw: String) -> Int? {
            switch raw {
            case "15m", "15 min", "15 mins", "15min", "15mins": return 15
            case "30m", "30 min", "30 mins", "30min", "30mins": return 30
            case "1h", "1 hr", "1 hour", "1hour": return 60
            case "3h", "3 hr", "3 hours", "3hours": return 180
            case "6h", "6 hr", "6 hours", "6hours": return 360
            case "12h", "12 hr", "12 hours", "12hours": return 720
            default: return nil
            }
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        let endDate: Date
        if isAllTimeLookahead {
            endDate = calendar.date(byAdding: .day, value: 365, to: now) ?? now.addingTimeInterval(365 * 24 * 3600)
        } else if isRestOfDay {
            endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(24 * 3600)
        } else if let minutes = lookaheadMinutes(from: lookaheadRaw) {
            endDate = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now.addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            endDate = calendar.date(byAdding: .minute, value: 180, to: now) ?? now.addingTimeInterval(180 * 60)
        }

        let calendarIDs = allCalendars.map { $0.id }
        let service = calendarService

        let fetched = await eventFetchLimiter.run {
            guard !Task.isCancelled else { return [EventModel]() }
            return await service.events(from: startDate, to: endDate, calendars: calendarIDs)
        }

        guard queryDemand.lockScreenEvents, !Task.isCancelled else { return }
        if lockScreenEvents == fetched {
            lastLockScreenEventsFetchDate = Date()
            return
        }

        withAnimation(.smooth(duration: 0.25)) {
            lockScreenEvents = fetched
        }
        lastLockScreenEventsFetchDate = Date()
    }

    func setLockScreenPreviewEvents(_ events: [EventModel]?) {
        lockScreenPreviewEvents = events
        guard let events else {
            Task { await updateLockScreenEvents(force: true) }
            return
        }
        withAnimation(.smooth(duration: 0.25)) {
            lockScreenEvents = events
        }
        lastLockScreenEventsFetchDate = Date()
    }

    private func startLockScreenRefreshLoop() {
        lockScreenRefreshTask?.cancel()
        let interval = refreshInterval * (runtimePolicy.isLowPower ? 2 : 1)
        lockScreenRefreshTask = Task { [weak self] in
            await self?.refreshForCurrentDemand()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.queryDemand.isActive else { return }
                await self.refreshForCurrentDemand()
            }
        }
    }

    private func updateEvents(force: Bool = false) async {
        guard (force || queryDemand.dayEvents), hasCalendarAccess || hasReminderAccess, !Task.isCancelled else { return }
        let now = Date()
        if !force, let lastFetch = lastEventsFetchDate, now.timeIntervalSince(lastFetch) < reloadRefreshInterval {
            return
        }
        
        Logger.log("CalendarManager: Updating events (force: \(force))", category: .lifecycle)

        let calendarIDs = selectedCalendars.map { $0.id }
        let startDate = currentWeekStartDate
        guard let endDate = Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate) else { return }
        let service = calendarService

        let events = await eventFetchLimiter.run {
            guard !Task.isCancelled else { return [EventModel]() }
            return await service.events(
                from: startDate,
                to: endDate,
                calendars: calendarIDs
            )
        }

        guard !Task.isCancelled else { return }
        self.events = events
        lastEventsFetchDate = Date()
    }

    /// Reminders always follow today, even when Home is browsing another date
    /// or stays hidden across midnight. Deadline scheduling remains independent.
    func refreshReminderEvents(force: Bool = false, now: Date = Date()) async {
        guard queryDemand.reminderEvents, !Task.isCancelled else { return }
        let day = CalendarManager.startOfDay(now)
        if !force, reminderSnapshotDay == day, let last = lastReminderEventsFetchDate,
           now.timeIntervalSince(last) < reloadRefreshInterval { return }
        let snapshot: [EventModel]
        if currentWeekStartDate == day, let last = lastEventsFetchDate,
           now.timeIntervalSince(last) < reloadRefreshInterval {
            snapshot = events
        } else {
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
            let service = calendarService
            let calendarIDs = selectedCalendars.map { $0.id }
            snapshot = await eventFetchLimiter.run {
                guard !Task.isCancelled else { return [EventModel]() }
                return await service.events(from: day, to: end, calendars: calendarIDs)
            }
        }
        guard queryDemand.reminderEvents, !Task.isCancelled else { return }
        if reminderEvents != snapshot { reminderEvents = snapshot }
        reminderSnapshotDay = day
        lastReminderEventsFetchDate = now
    }

    func setCalendarsSelected(_ calendars: [CalendarModel], isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]
        let ids = Set(calendars.map { $0.id })

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting(ids)
                selectionState = .selected(identifiers)
            }
        case .selected(var identifiers):
            if isSelected {
                identifiers.formUnion(ids)
            } else {
                identifiers.subtract(ids)
            }

            if identifiers.isEmpty || identifiers.count == allCalendars.count {
                selectionState = .all
            } else {
                selectionState = .selected(identifiers)
            }
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents(force: true)
        await refreshReminderEvents(force: true)
        await updateLockScreenEvents(force: true)
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        await updateEvents(force: true)
        await refreshReminderEvents(force: true)
    }
}

// MARK: - Event Fetch Limiter

private actor EventFetchLimiter {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isRunning = false

    func run<T>(_ operation: @escaping @Sendable () async -> T) async -> T {
        await waitTurn()
        defer { resumeNext() }
        return await operation()
    }

    private func waitTurn() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeNext() {
        if waiters.isEmpty {
            isRunning = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
