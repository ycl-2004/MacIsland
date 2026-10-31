import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

/// Recurrence is a pure function of (item, reference date, calendar), which is
/// the only way to test month lengths, weekdays and "already passed" without a
/// run loop. A fixed UTC calendar keeps the expectations readable.
final class MicroEventTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    // MARK: - Recurrence

    func testDailyUsesTodayWhenTheTimeIsStillAhead() {
        let item = MicroEvent(title: "Stand-up", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 3, 1))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 3, 10, 8, 0), calendar: calendar),
                       date(2026, 3, 10, 9, 0))
    }

    func testDailyMovesToTomorrowAfterTheTime() {
        let item = MicroEvent(title: "Stand-up", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 3, 1))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 3, 10, 9, 30), calendar: calendar),
                       date(2026, 3, 11, 9, 0))
    }

    func testDailyDoesNotStartBeforeItsStartDate() {
        let item = MicroEvent(title: "Review", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 3, 10, 0, 0))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 3, 1, 0, 0), calendar: calendar),
                       date(2026, 3, 10, 9, 0),
                       "The first occurrence is on the start date, never before it")
        XCTAssertNil(item.occurrence(onDayOf: date(2026, 3, 5, 12, 0), calendar: calendar),
                     "A day before the start date has no occurrence")
    }

    func testWeeklySkipsToTheNextSelectedWeekday() {
        // 2026-03-11 is a Wednesday; Monday is weekday 2.
        let item = MicroEvent(title: "Review", recurrence: .weekly, hour: 18, minute: 30,
                              weekdays: [2], startDate: date(2026, 3, 1))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 3, 11, 12, 0), calendar: calendar),
                       date(2026, 3, 16, 18, 30))
    }

    func testWeeklyWithNoWeekdaysNeverMatches() {
        let item = MicroEvent(title: "Review", recurrence: .weekly, hour: 18, minute: 0,
                              weekdays: [], startDate: date(2026, 3, 1))
        XCTAssertNil(item.nextOccurrence(after: date(2026, 3, 11, 12, 0), calendar: calendar))
        XCTAssertEqual(item.normalized(calendar: calendar).weekdays.count, 1,
                       "Saving repairs an empty weekly rule with the start weekday")
    }

    func testMonthlyClampsTheThirtyFirstToShortMonths() {
        // 2026 is not a leap year, so February has 28 days.
        let item = MicroEvent(title: "Invoice", recurrence: .monthly, hour: 10, minute: 0,
                              dayOfMonth: 31, startDate: date(2026, 1, 1))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 1, 31, 12, 0), calendar: calendar),
                       date(2026, 2, 28, 10, 0))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 2, 28, 12, 0), calendar: calendar),
                       date(2026, 3, 31, 10, 0))
    }

    func testOnceFiresOnceAndNeverAgain() {
        let item = MicroEvent(title: "Renew", recurrence: .once,
                              startDate: date(2026, 4, 1, 9, 0))
        XCTAssertEqual(item.nextOccurrence(after: date(2026, 3, 1), calendar: calendar),
                       date(2026, 4, 1, 9, 0))
        XCTAssertNil(item.nextOccurrence(after: date(2026, 4, 1, 9, 0), calendar: calendar))
    }

    func testPastTimeIsNotReturnedAsTheNextOccurrence() {
        let item = MicroEvent(title: "Water", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 3, 1))
        // Reopening the app at 10:00 must not schedule this morning's 09:00 again.
        let next = item.nextOccurrence(after: date(2026, 3, 10, 10, 0), calendar: calendar)
        XCTAssertEqual(next, date(2026, 3, 11, 9, 0))
        XCTAssertGreaterThan(next!, date(2026, 3, 10, 10, 0))
    }

    // MARK: - Today's occurrence and completion

    func testTodaysRowCanBeTickedBeforeItsTime() {
        let item = MicroEvent(title: "Water", recurrence: .daily, hour: 18, minute: 0,
                              startDate: date(2026, 3, 1))
        XCTAssertEqual(item.currentOrNextOccurrence(from: date(2026, 3, 10, 9, 0), calendar: calendar),
                       date(2026, 3, 10, 18, 0))
    }

    func testCompletionBelongsToOneOccurrenceOnly() {
        let item = MicroEvent(title: "Water", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 3, 1))
        let today = date(2026, 3, 10, 9, 0)
        let tomorrow = date(2026, 3, 11, 9, 0)
        let done = item.markingCompleted(today, calendar: calendar)
        XCTAssertTrue(done.isCompleted(today, calendar: calendar))
        XCTAssertFalse(done.isCompleted(tomorrow, calendar: calendar),
                       "Tomorrow starts unchecked")
        XCTAssertFalse(done.clearingCompletion(today, calendar: calendar).isCompleted(today, calendar: calendar))
    }

    func testCompletionHistoryIsBounded() {
        let item = MicroEvent(title: "Water", recurrence: .daily, hour: 9, minute: 0,
                              startDate: date(2026, 1, 1))
        var done = item
        for offset in 0..<(MicroEvent.completedKeyLimit + 20) {
            done = done.markingCompleted(date(2026, 1, 1).addingTimeInterval(86_400 * Double(offset)),
                                         calendar: calendar)
        }
        XCTAssertEqual(done.completedKeys.count, MicroEvent.completedKeyLimit)
    }

    func testCompletionSurvivesEncoding() throws {
        let item = MicroEvent(title: "Water", recurrence: .weekly, hour: 9, minute: 15,
                              weekdays: [2, 4], startDate: date(2026, 3, 1))
            .markingCompleted(date(2026, 3, 2, 9, 15), calendar: calendar)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(MicroEvent.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    // MARK: - Normalisation

    func testNormalisationTrimsAndClamps() {
        let item = MicroEvent(title: "  Read  ", recurrence: .monthly, hour: 99, minute: -4,
                              dayOfMonth: 0, startDate: date(2026, 3, 1))
        let normalized = item.normalized(calendar: calendar)
        XCTAssertEqual(normalized.title, "Read")
        XCTAssertEqual(normalized.hour, 23)
        XCTAssertEqual(normalized.minute, 0)
        XCTAssertEqual(normalized.dayOfMonth, 1)
    }

    func testEmptyTitleIsNotValid() {
        XCTAssertFalse(MicroEvent(title: "   ", recurrence: .daily).isValid)
        XCTAssertTrue(MicroEvent(title: "Water", recurrence: .daily).isValid)
    }

    @MainActor
    func testCompletedOccurrenceIsSkippedWhenSchedulingAtItsDeliveryTime() {
        let today = date(2026, 3, 10, 9)
        let completed = MicroEvent(title: "Water", recurrence: .daily, hour: 9,
                                   startDate: date(2026, 3, 1)).markingCompleted(today, calendar: calendar)
        let next = MicroEventManager.nextDelivery(for: completed, now: today, lead: 0, calendar: calendar)
        XCTAssertEqual(next?.occurrence, date(2026, 3, 11, 9))

        let once = MicroEvent(title: "Once", recurrence: .once, startDate: today)
            .markingCompleted(today, calendar: calendar)
        XCTAssertNil(MicroEventManager.nextDelivery(for: once, now: today, lead: 0, calendar: calendar))
    }

    @MainActor
    func testCompletedEarlyReminderDoesNotPreventAnotherEvent() {
        let now = date(2026, 3, 10, 8, 50)
        let completed = MicroEvent(title: "Done", recurrence: .daily, hour: 9,
                                   startDate: date(2026, 3, 1))
            .markingCompleted(date(2026, 3, 10, 9), calendar: calendar)
        let other = MicroEvent(title: "Next", recurrence: .daily, hour: 9, minute: 5,
                               startDate: date(2026, 3, 1))
        let deliveries = [completed, other].compactMap {
            MicroEventManager.nextDelivery(for: $0, now: now, lead: 600, calendar: calendar)
        }
        XCTAssertEqual(deliveries.min(by: { $0.delivery < $1.delivery })?.delivery, date(2026, 3, 10, 8, 55))
    }

    @MainActor
    func testEarlyReminderRefreshesAtActualDueTime() {
        let now = date(2026, 3, 10, 8, 40)
        let due = date(2026, 3, 10, 9)
        let item = MicroEvent(title: "Due later", recurrence: .daily, hour: 9,
                              startDate: date(2026, 3, 1))
        XCTAssertEqual(MicroEventManager.nextDueStateChange(events: [item], now: now, calendar: calendar), due)
        let done = item.markingCompleted(due, calendar: calendar)
        XCTAssertNil(MicroEventManager.nextDueStateChange(events: [done], now: now, calendar: calendar))
    }

    func testOneOffCombinesSelectedDateWithLatestTypedTime() {
        var item = MicroEvent(title: "Appointment", recurrence: .once, hour: 9, minute: 0,
                              startDate: date(2026, 12, 20, 9))
        item.hour = 16
        item.minute = 45
        XCTAssertEqual(item.onceDate(calendar: calendar), date(2026, 12, 20, 16, 45))
        item.startDate = date(2027, 2, 14, 9)
        XCTAssertEqual(item.onceDate(calendar: calendar), date(2027, 2, 14, 16, 45))
    }

    // MARK: - Time input

    func testTimeParserAcceptsCommonForms() {
        XCTAssertEqual(MicroEventTimeParser.time(from: "9"), .init(hour: 9, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "930"), .init(hour: 9, minute: 30))
        XCTAssertEqual(MicroEventTimeParser.time(from: "2130"), .init(hour: 21, minute: 30))
        XCTAssertEqual(MicroEventTimeParser.time(from: "9pm"), .init(hour: 21, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "9:00"), .init(hour: 9, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "09:05"), .init(hour: 9, minute: 5))
        XCTAssertEqual(MicroEventTimeParser.time(from: "21:30"), .init(hour: 21, minute: 30))
        XCTAssertEqual(MicroEventTimeParser.time(from: "9:00 PM"), .init(hour: 21, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "9:00pm"), .init(hour: 21, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "12:00 AM"), .init(hour: 0, minute: 0))
        XCTAssertEqual(MicroEventTimeParser.time(from: "12:30 PM"), .init(hour: 12, minute: 30))
    }

    func testTimeParserRejectsInvalidInput() {
        XCTAssertNil(MicroEventTimeParser.time(from: ""))
        XCTAssertNil(MicroEventTimeParser.time(from: "25:00"))
        XCTAssertNil(MicroEventTimeParser.time(from: "9:75"))
        XCTAssertNil(MicroEventTimeParser.time(from: "nine"))
        XCTAssertNil(MicroEventTimeParser.time(from: "13pm"))
        XCTAssertNil(MicroEventTimeParser.time(from: "0am"))
        XCTAssertNil(MicroEventTimeParser.time(from: "-1:00"))
        XCTAssertNil(MicroEventTimeParser.time(from: "12345"))
    }

    func testScheduleDescriptionShowsTheRepeatType() {
        for recurrence in MicroEventRecurrence.allCases {
            let event = MicroEvent(title: "Test", recurrence: recurrence, hour: 9,
                                   weekdays: [2], startDate: date(2026, 3, 1))
            XCTAssertTrue(event.scheduleDescription.hasPrefix(recurrence.localizedName),
                          "The displayed schedule must identify \(recurrence.rawValue)")
        }
    }

    func testOverdueStateExcludesCompletedAndPausedItems() {
        let now = date(2026, 3, 10, 10)
        let due = date(2026, 3, 10, 9)
        let item = MicroEvent(title: "Test", recurrence: .daily, hour: 9, startDate: date(2026, 3, 1))
        func row(_ event: MicroEvent, _ occurrence: Date) -> MicroEventRow {
            MicroEventRow(event: event, now: now, occurrence: occurrence,
                          onToggle: {}, onEdit: {}, onToggleEnabled: {}, onDelete: {})
        }
        XCTAssertTrue(row(item, due).isOverdue)
        XCTAssertFalse(row(item, date(2026, 3, 10, 11)).isOverdue)
        XCTAssertFalse(row(item.markingCompleted(due), due).isOverdue)
        var paused = item
        paused.isEnabled = false
        XCTAssertFalse(row(paused, due).isOverdue)
    }

    @MainActor
    func testEditingKeepsNotchOpenAndReleasesSuppressionOnDismissal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-focus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"))
        let vm = DynamicIslandViewModel()
        let event = MicroEvent(title: "Edit time", recurrence: .daily)
        let host = NSHostingView(rootView: NotchMicroEventsView(store: store, draft: event).environmentObject(vm))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(vm.isAutoCloseSuppressed, "An active editor must prevent hover-exit closing")
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(vm.isAutoCloseSuppressed, "Leaving the editor must release its suppression")
    }

    @MainActor
    func testTypingAndSavingTimeInNotchEditor() async throws {
        let previous = Defaults[.enableMicroEventsFeature]
        Defaults[.enableMicroEventsFeature] = true
        defer { Defaults[.enableMicroEventsFeature] = previous }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-time-ui-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"), saveDelay: 30)
        store.loadIfNeeded()
        let vm = DynamicIslandViewModel()
        let event = MicroEvent(title: "Edit time", recurrence: .daily, hour: 9)
        let root = NotchMicroEventsView(store: store, draft: event).environmentObject(vm)
            .frame(width: 480, height: 160).background(Color.black)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))

        func click(_ point: NSPoint) async throws {
            func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 1, clickCount: 1, pressure: 1))
            }
            // NSTextView can synchronously track until mouse-up. Queue that
            // event before dispatching mouse-down so CI cannot deadlock.
            NSApp.postEvent(try mouse(.leftMouseUp), atStart: true)
            window.sendEvent(try mouse(.leftMouseDown))
            try await Task.sleep(for: .milliseconds(60))
        }
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) async throws {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let key = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil,
                                                        characters: characters, charactersIgnoringModifiers: characters,
                                                        isARepeat: false, keyCode: code))
                NSApp.sendEvent(key)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        try await click(NSPoint(x: 120, y: 107))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(vm.isAutoCloseSuppressed)
        let focusedBeforeTyping = String(describing: window.firstResponder)
        let wasKey = window.isKeyWindow
        // Other UI tests can leave this host app inactive. Select the field's
        // contents directly so the test does not depend on a global key-window
        // shortcut, then exercise actual key events for the time and Return.
        let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView, "The time field must receive focus")
        fieldEditor.selectAll(nil)
        try await key("9", code: 25)
        try await key("3", code: 20)
        try await key("0", code: 29)
        let typedText = (window.firstResponder as? NSTextView)?.string ?? "<no field editor>"
        XCTAssertEqual(typedText, "930")
        try await key("\r", code: 36)
        try await click(NSPoint(x: 450, y: 72))
        try await Task.sleep(for: .milliseconds(100))
        if store.events.isEmpty, let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let image = bitmap.representation(using: .png, properties: [:]) {
                attachPreview(image, named: "micro-events-time-save-failure")
            }
        }
        let saved = try XCTUnwrap(store.events.first, "The typed time should save from the editor; key=\(wasKey), responder=\(focusedBeforeTyping), typed=\(typedText), currentKey=\(String(describing: NSApp.keyWindow))")
        XCTAssertEqual(saved.hour, 9)
        XCTAssertEqual(saved.minute, 30)
    }

    // MARK: - Store

    func testStoreWritesAndReadsBackItsItems() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-micro-events-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")

        let store = await MicroEventStore(fileURL: url, saveDelay: 0)
        await store.loadIfNeeded()
        await store.add(MicroEvent(title: "Water", recurrence: .daily, hour: 9, minute: 0))
        await store.add(MicroEvent(title: "Review", recurrence: .weekly, hour: 18, minute: 0,
                                   weekdays: [2, 5]))
        await store.saveNow()

        try await waitFor { FileManager.default.fileExists(atPath: url.path) }

        let reloaded = await MicroEventStore(fileURL: url, saveDelay: 0)
        await reloaded.loadIfNeeded()
        let titles = await reloaded.events.map(\.title)
        XCTAssertEqual(titles, ["Water", "Review"])
        let weekly = await reloaded.events.last
        XCTAssertEqual(weekly?.weekdays, [2, 5])
    }

    func testUnreadableFileIsKeptInsteadOfOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-micro-events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        try Data("not json".utf8).write(to: url)

        let store = await MicroEventStore(fileURL: url, saveDelay: 0)
        await store.loadIfNeeded()
        let error = await store.errorMessage
        XCTAssertNotNil(error)
        let quarantined = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("events.unreadable-") }
        XCTAssertEqual(quarantined.count, 1, "The unreadable list is preserved, not replaced")
        let empty = await store.events.isEmpty
        XCTAssertTrue(empty)
    }

    @MainActor
    func testCreateReadEditAndDeleteSurviveReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-crud-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        let store = MicroEventStore(fileURL: url, saveDelay: 30)
        store.loadIfNeeded()
        store.add(MicroEvent(title: "Read daily", recurrence: .daily, hour: 9))
        let original = try XCTUnwrap(store.events.first)
        let created = await store.saveForTermination()
        XCTAssertNil(created)

        let read = MicroEventStore(fileURL: url, saveDelay: 30)
        read.loadIfNeeded()
        XCTAssertEqual(read.events.map(\.title), ["Read daily"])
        var updated = try XCTUnwrap(read.events.first)
        updated.title = "Read on Mondays"
        updated.recurrence = .weekly
        updated.weekdays = [2]
        updated.hour = 18
        read.update(updated)
        let saved = await read.saveForTermination()
        XCTAssertNil(saved)

        let edited = MicroEventStore(fileURL: url, saveDelay: 30)
        edited.loadIfNeeded()
        let result = try XCTUnwrap(edited.events.first)
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.title, "Read on Mondays")
        XCTAssertEqual(result.recurrence, .weekly)
        XCTAssertEqual(result.weekdays, [2])
        XCTAssertEqual(result.hour, 18)
        edited.remove(id: result.id)
        let deleted = await edited.saveForTermination()
        XCTAssertNil(deleted)
        let afterDelete = MicroEventStore(fileURL: url)
        afterDelete.loadIfNeeded()
        XCTAssertTrue(afterDelete.events.isEmpty)
    }

    @MainActor
    func testOneOffCleanupUsesLocalDayAndPreservesFutureAndPausedItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-cleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"), saveDelay: 30)
        store.loadIfNeeded()
        let now = date(2026, 3, 11, 8)
        let doneYesterday = MicroEvent(title: "Done yesterday", recurrence: .once,
                                       startDate: date(2026, 3, 15, 9))
            .markingCompleted(date(2026, 3, 15, 9), calendar: calendar, completedAt: date(2026, 3, 10, 23, 59))
        let doneToday = MicroEvent(title: "Done today", recurrence: .once,
                                   startDate: date(2026, 3, 15, 9))
            .markingCompleted(date(2026, 3, 15, 9), calendar: calendar, completedAt: date(2026, 3, 11, 0))
        store.add(doneYesterday)
        store.add(doneToday)
        store.add(MicroEvent(title: "Overdue yesterday", recurrence: .once, startDate: date(2026, 3, 10, 23, 59)))
        store.add(MicroEvent(title: "Overdue today", recurrence: .once, startDate: date(2026, 3, 11, 7)))
        store.add(MicroEvent(title: "Future", recurrence: .once, startDate: date(2026, 3, 12, 9)))
        store.add(MicroEvent(title: "Paused", recurrence: .once, startDate: date(2026, 3, 9, 9), isEnabled: false))
        store.add(MicroEvent(title: "Recurring", recurrence: .daily, startDate: date(2026, 3, 1)))
        store.cleanupExpiredOccurrences(now: now, calendar: calendar)
        XCTAssertEqual(Set(store.events.map(\.title)), Set(["Done today", "Overdue today", "Future", "Paused", "Recurring"]))
    }

    @MainActor
    func testLegacyCompletedPastOneOffIsCleanedOnRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-legacy-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        let item = MicroEvent(title: "Older completed item", recurrence: .once, startDate: Date().addingTimeInterval(-86_400),
                              completedKeys: [MicroEvent.onceKey])
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        raw.removeValue(forKey: "completedAt")
        try JSONSerialization.data(withJSONObject: ["version": 1, "events": [raw]]).write(to: url)
        let store = MicroEventStore(fileURL: url, saveDelay: 30)
        store.loadIfNeeded()
        XCTAssertNotNil(store.events.first?.completedAt)
        store.cleanupExpiredOccurrences(now: Date())
        XCTAssertTrue(store.events.isEmpty, "An old legacy completion is removed on restart")
    }

    @MainActor
    func testRestartCleanupPersistsWithoutStaleBackupOrRecurringHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-restart-cleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        let original = MicroEventStore(fileURL: url, saveDelay: 30)
        original.loadIfNeeded()
        original.add(MicroEvent(title: "Expired one-off", recurrence: .once, startDate: date(2026, 10, 31, 9)))
        let recurring = MicroEvent(title: "Keep recurring", recurrence: .daily, startDate: date(2026, 10, 1))
            .markingCompleted(date(2026, 10, 31, 9), calendar: calendar)
            .markingCompleted(date(2026, 11, 1, 9), calendar: calendar)
        original.add(recurring)
        let initialFailure = await original.saveForTermination()
        XCTAssertNil(initialFailure)

        let restarted = MicroEventStore(fileURL: url, saveDelay: 30)
        restarted.loadIfNeeded()
        restarted.cleanupExpiredOccurrences(now: date(2026, 11, 1, 0), calendar: calendar)
        let saveFailure = await restarted.saveForTermination()
        XCTAssertNil(saveFailure)
        XCTAssertEqual(restarted.events.map(\.title), ["Keep recurring"])
        XCTAssertEqual(restarted.events.first?.completedKeys, ["2026-11-01"])
        for name in ["events.json", "events.previous.json"] {
            let contents = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(contents.contains("Expired one-off"), "\(name) must not retain the deleted item")
            XCTAssertFalse(contents.contains("2026-10-31"), "\(name) must not retain old occurrence markers")
            XCTAssertTrue(contents.contains("Keep recurring"))
        }
        let reloaded = MicroEventStore(fileURL: url, saveDelay: 30)
        reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.events.map(\.title), ["Keep recurring"])
    }

    @MainActor
    func testMidnightCleanupDefersWhileAnyEditorIsOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-editor-cleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"), saveDelay: 30)
        store.loadIfNeeded()
        let item = MicroEvent(title: "Editing", recurrence: .once, startDate: date(2026, 3, 10, 9))
        store.add(item)
        let first = UUID(), second = UUID(), tomorrow = date(2026, 3, 11, 0)
        store.beginEditing(id: item.id, token: first)
        store.beginEditing(id: item.id, token: second)
        store.cleanupExpiredOccurrences(now: tomorrow, calendar: calendar)
        XCTAssertEqual(store.events.count, 1)
        store.endEditing(token: first, performCleanup: true, now: tomorrow, calendar: calendar)
        XCTAssertEqual(store.events.count, 1, "Another window is still editing the item")
        store.endEditing(token: second, performCleanup: true, now: tomorrow, calendar: calendar)
        XCTAssertTrue(store.events.isEmpty, "Cleanup resumes once editing ends")
    }

    @MainActor
    func testEndingEditDoesNotCleanUpWhenFeatureIsDisabled() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-disabled-edit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"), saveDelay: 30)
        store.loadIfNeeded()
        let item = MicroEvent(title: "Past", recurrence: .once, startDate: date(2026, 3, 10, 9))
        store.add(item)
        let token = UUID()
        store.beginEditing(id: item.id, token: token)
        store.endEditing(token: token, performCleanup: false, now: date(2026, 3, 11), calendar: calendar)
        XCTAssertEqual(store.events.count, 1, "Editing while reminders are disabled must not remove an item")
    }

    @MainActor
    func testTerminationSaveWaitsForLatestEditAndReportsFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-quit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.json")
        let store = MicroEventStore(fileURL: url, saveDelay: 30)
        store.loadIfNeeded()
        store.add(MicroEvent(title: "Latest", recurrence: .daily))
        let result = await store.saveForTermination()
        XCTAssertNil(result)
        let reloaded = MicroEventStore(fileURL: url)
        reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.events.map(\.title), ["Latest"])

        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        let blocked = MicroEventStore(fileURL: blockedParent.appendingPathComponent("events.json"), saveDelay: 30)
        blocked.loadIfNeeded()
        blocked.add(MicroEvent(title: "Unsaved", recurrence: .daily))
        let gate = TerminationSaveGate { await blocked.saveForTermination() }
        let done = expectation(description: "quit refused")
        gate.prepare { error in XCTAssertNotNil(error); done.fulfill() }
        await fulfillment(of: [done], timeout: 3)
    }

    @MainActor
    func testRenderMicroEventEditorAndEmptyState() async throws {
        let previous = Defaults[.enableMicroEventsFeature]
        Defaults[.enableMicroEventsFeature] = true
        defer { Defaults[.enableMicroEventsFeature] = previous }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"))
        store.loadIfNeeded()
        let vm = DynamicIslandViewModel()
        let drafts: [(String, MicroEvent?)] = [
            ("empty", nil),
            ("once", MicroEvent(title: "Annual appointment", recurrence: .once, hour: 16, minute: 30,
                                startDate: Date().addingTimeInterval(90 * 86_400))),
            ("weekly", MicroEvent(title: "Walk", recurrence: .weekly, hour: 9, weekdays: [2, 4]))
        ]
        for (name, draft) in drafts {
            let root = NotchMicroEventsView(store: store, draft: draft)
                .environmentObject(vm).frame(width: 480, height: 160).background(Color.black)
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 160)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            attachPreview(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), named: "micro-events-\(name)")
            window.contentView = nil
            window.close()
        }
    }

    @MainActor
    func testRenderMicroEventManagementAndPopulatedNotch() async throws {
        let previous = Defaults[.enableMicroEventsFeature]
        Defaults[.enableMicroEventsFeature] = true
        defer { Defaults[.enableMicroEventsFeature] = previous }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-manage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"), saveDelay: 30)
        store.loadIfNeeded()
        store.add(MicroEvent(title: "Drink water", recurrence: .daily, hour: 0,
                             startDate: Calendar.autoupdatingCurrent.startOfDay(for: Date())))
        let event = try XCTUnwrap(store.events.first)

        func capture<V: View>(_ view: V, size: NSSize, name: String) async throws {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            attachPreview(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), named: name)
            window.contentView = nil
            window.close()
        }
        try await capture(MicroEventSettings(store: store).environmentObject(SettingsHighlightCoordinator()).frame(width: 560, height: 650),
                          size: NSSize(width: 560, height: 650), name: "micro-events-settings-list")
        try await capture(MicroEventSettingsEditor(editing: MicroEventEditing(event: event, isNew: false),
                                                   onSave: { _ in }, onCancel: {}).frame(width: 460, height: 400),
                          size: NSSize(width: 460, height: 400), name: "micro-events-settings-editor")
        try await capture(NotchMicroEventsView(store: store).environmentObject(DynamicIslandViewModel())
            .frame(width: 480, height: 160).background(Color.black),
                          size: NSSize(width: 480, height: 160), name: "micro-events-notch-list")
    }

    @MainActor
    func testDoubleClickingEventRowOpensEditAction() async throws {
        var edited = false
        let item = MicroEvent(title: "Double click to edit", recurrence: .daily)
        let row = MicroEventRow(event: item, now: Date(), occurrence: Date().addingTimeInterval(600),
                                onToggle: {}, onEdit: { edited = true }, onToggleEnabled: {}, onDelete: {})
        let host = NSHostingView(rootView: row.frame(width: 480, height: 28).background(Color.black))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 28)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        for count in 1...2 {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 70, y: 14),
                                                            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                            windowNumber: window.windowNumber, context: nil,
                                                            eventNumber: count, clickCount: count, pressure: 1))
                NSApp.sendEvent(event)
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(edited, "Double-clicking the event text should open its editor")
    }

    @MainActor
    func testRepeatSelectorOpensItsOptions() async throws {
        let previous = Defaults[.enableMicroEventsFeature]
        Defaults[.enableMicroEventsFeature] = true
        defer { Defaults[.enableMicroEventsFeature] = previous }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-micro-menu-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicroEventStore(fileURL: directory.appendingPathComponent("events.json"))
        let draft = MicroEvent(title: "Menu test", recurrence: .daily)
        let root = NotchMicroEventsView(store: store, draft: draft).environmentObject(DynamicIslandViewModel())
            .frame(width: 480, height: 160).background(Color.black)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let before = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        // Dispatch to the test window directly: the full suite can leave the
        // test host inactive, in which case NSApp may drop a synthetic click.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 40, y: 107),
                                                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil,
                                                        eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(300))
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        XCTAssertTrue(visibleWindows.contains { !before.contains($0.windowNumber) },
                      "Clicking Repeat should open the menu of recurrence choices; before=\(before), visible=\(visibleWindows.map { "\($0.windowNumber):\(type(of: $0))" })")
    }

    // MARK: - Tab wiring

    func testMicroEventsTabIsOffUntilEnabled() {
        let saved = Defaults[.enableMicroEventsFeature]
        defer { Defaults[.enableMicroEventsFeature] = saved }
        Defaults[.enableMicroEventsFeature] = false
        XCTAssertFalse(NotchTabAvailability.current.tabs.contains(.microEvents))

        Defaults[.enableMicroEventsFeature] = true
        XCTAssertTrue(NotchTabAvailability.current.tabs.contains(.microEvents))
        XCTAssertEqual(NotchTabAvailability.current.resolve(.microEvents), .microEvents)

        Defaults[.enableMicroEventsFeature] = false
        let availability = NotchTabAvailability.current
        XCTAssertNotEqual(availability.resolve(.microEvents), .microEvents,
                          "A disabled tab resolves to the first enabled one")
    }

    func testSavedOrderPositionIsHonoured() {
        let availability = NotchTabAvailability(
            home: true, shelf: false, timer: false, stats: false, agents: false,
            extraSpace: false, microEvents: true, colorPicker: false,
            order: ["microEvents", "home"])
        XCTAssertEqual(availability.tabs, [.microEvents, .home])
    }

    func testTabIconExistsOnThisSystem() {
        XCTAssertNotNil(NSImage(systemSymbolName: "checklist", accessibilityDescription: nil),
                        "The tab and reminder peek use this symbol")
    }

    private func waitFor(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
