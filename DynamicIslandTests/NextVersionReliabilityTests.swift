import AppKit
import Defaults
import EventKit
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class NextVersionReliabilityTests: XCTestCase {
    func testRoutingUsesSavedOrderAndKeepsColorPickerSeparate() {
        let availability = NotchTabAvailability(home: false, shelf: false, timer: false,
            stats: true, agents: true, extraSpace: false, colorPicker: true, order: ["agents", "stats"])
        XCTAssertEqual(availability.tabs, [.agents, .stats])
        for target in [NotchViews.home, .shelf, .extraSpace, .timer] {
            XCTAssertEqual(availability.resolve(target), .agents)
        }
        XCTAssertEqual(availability.resolve(.stats), .stats)
        XCTAssertEqual(availability.resolve(.colorPicker), .colorPicker)
        let empty = NotchTabAvailability(home: false, shelf: false, timer: false,
            stats: false, agents: false, extraSpace: false, colorPicker: false)
        XCTAssertEqual(empty.resolve(.extraSpace), .home)
        XCTAssertFalse(empty.contains(empty.resolve(.extraSpace)), "Sentinel renders the setup entry")
    }

    func testCoordinatorRoutesDisabledCurrentRememberedAndShortcutTargets() {
        var available = NotchTabAvailability(home: false, shelf: false, timer: false,
            stats: true, agents: true, extraSpace: true, colorPicker: true, order: ["agents", "stats", "extraSpace"])
        let coordinator = DynamicIslandViewCoordinator(availability: { available }, observeDefaults: false)
        coordinator.currentView = .extraSpace
        coordinator.lastActiveView = .extraSpace
        available = NotchTabAvailability(home: false, shelf: false, timer: false,
            stats: true, agents: true, extraSpace: false, colorPicker: true, order: ["agents", "stats"])
        coordinator.ensureValidSelection()
        XCTAssertEqual(coordinator.currentView, .agents)
        XCTAssertEqual(coordinator.lastActiveView, .agents)
        coordinator.currentView = .home // same setter used by default-tab shortcuts
        XCTAssertEqual(coordinator.currentView, .agents)
        coordinator.currentView = .stats
        XCTAssertEqual(coordinator.currentView, .stats)
        coordinator.currentView = .colorPicker
        XCTAssertEqual(coordinator.currentView, .colorPicker)
        available = NotchTabAvailability(home: false, shelf: false, timer: false,
            stats: false, agents: false, extraSpace: false, colorPicker: false)
        coordinator.ensureValidSelection()
        XCTAssertEqual(coordinator.currentView, .home)
        XCTAssertFalse(available.contains(coordinator.currentView))
    }

    func testCalendarServiceOnlyQueriesForDemandAndPreservesReminderConsumer() async throws {
        let service = CalendarFixture()
        let manager = CalendarManager(service: service, observeRuntime: false, refreshInterval: 0.02)
        manager.calendarAuthorizationStatus = .fullAccess
        var policy = AtollRuntimePolicy()
        manager.setQueryDemand(policy: policy, remindersEnabled: false, lockScreenEnabled: false)
        await manager.refreshForCurrentDemand()
        XCTAssertEqual(service.queries, 0)
        policy.calendarVisible = true
        manager.setQueryDemand(policy: policy, remindersEnabled: false, lockScreenEnabled: false)
        try await waitUntil { service.queries == 1 }
        policy.calendarVisible = false
        manager.setQueryDemand(policy: policy, remindersEnabled: false, lockScreenEnabled: false)
        try await Task.sleep(for: .milliseconds(50))
        await manager.refreshForCurrentDemand()
        XCTAssertEqual(service.queries, 1)
        policy.isLocked = true
        manager.setQueryDemand(policy: policy, remindersEnabled: false, lockScreenEnabled: true)
        try await waitUntil { service.queries == 2 }
        XCTAssertTrue(manager.queryDemand.lockScreenEvents)
        manager.setQueryDemand(policy: policy, remindersEnabled: true, lockScreenEnabled: false)
        XCTAssertTrue(manager.queryDemand.dayEvents, "Reminder consumer survives hidden Home and lock")
        XCTAssertFalse(manager.queryDemand.lockScreenEvents)
        manager.calendarAuthorizationStatus = .denied
        manager.setQueryDemand(policy: policy, remindersEnabled: true, lockScreenEnabled: true)
        XCTAssertFalse(manager.queryDemand.isActive)
        let count = service.queries
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(service.queries, count)
        XCTAssertEqual(service.permissionRequests, 0)
    }

    func testReminderSnapshotFollowsTodayAndRollsAcrossMidnightIndependentlyOfHome() async throws {
        let service = CalendarFixture()
        let manager = CalendarManager(service: service, observeRuntime: false)
        manager.calendarAuthorizationStatus = .fullAccess
        let today = CalendarManager.startOfDay(Date())
        manager.currentWeekStartDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 5, to: today))
        manager.setQueryDemand(policy: AtollRuntimePolicy(), remindersEnabled: true, lockScreenEnabled: false)
        defer { manager.setQueryDemand(policy: AtollRuntimePolicy(), remindersEnabled: false, lockScreenEnabled: false) }
        try await waitUntil { service.queries == 1 }
        XCTAssertEqual(service.queryDates, [today])
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        await manager.refreshReminderEvents(now: tomorrow)
        XCTAssertEqual(service.queryDates, [today, tomorrow])
    }

    func testReminderCompletionImmediatelyUpdatesTheIndependentSnapshot() async throws {
        let service = CalendarFixture()
        service.includesReminder = true
        let manager = CalendarManager(service: service, observeRuntime: false)
        manager.reminderAuthorizationStatus = .fullAccess
        manager.setQueryDemand(policy: AtollRuntimePolicy(), remindersEnabled: true, lockScreenEnabled: false)
        defer { manager.setQueryDemand(policy: AtollRuntimePolicy(), remindersEnabled: false, lockScreenEnabled: false) }
        try await waitUntil { manager.reminderEvents.count == 1 }
        XCTAssertEqual(manager.reminderEvents.first?.type, .reminder(completed: false))
        await manager.setReminderCompleted(reminderID: "fixture-reminder", completed: true)
        XCTAssertEqual(manager.reminderEvents.first?.type, .reminder(completed: true))
        XCTAssertEqual(service.permissionRequests, 0)
    }

    func testShelfDisableRetainsContentAcrossPersistenceAndExplicitClear() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "shelf-disable-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = Defaults.Key<Bool>("enabled", default: true, suite: defaults)
        let persistence = ShelfPersistenceService(directory: folder.appendingPathComponent("store"))
        let item = ShelfItem(kind: .text(string: "Keep this content"))
        persistence.save([item])
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("temporary"))
        let thumbnails = ThumbnailService(lifetime: lifetime)
        let manager = ShelfStateViewModel(persistence: persistence, lifetime: lifetime, enabledKey: key, thumbnails: thumbnails)
        Defaults[key] = false // also exercises disabling before the asynchronous load finishes
        try await waitUntil { manager.isLoaded }
        XCTAssertEqual(manager.items.map(\.id), [item.id])
        manager.flushPendingSave()
        XCTAssertEqual(persistence.load().map(\.id), [item.id])
        Defaults[key] = true
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(manager.items.map(\.id), [item.id])
        manager.removeAll(); manager.flushPendingSave()
        XCTAssertTrue(persistence.load().isEmpty)
    }

    func testReadOnlyFindBarOpensAndCancelsWithoutEditingOrChangingUndo() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("text.txt")
        try "中文 text\nneedle and needle".write(to: url, atomically: true, encoding: .utf8)
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let hosting = NSHostingView(rootView: ExtraSpaceEditor(store: store, screenID: UUID().uuidString,
            isEditing: false, onFocusChange: { _ in }, onClose: {}))
        hosting.sizingOptions = []
        let window = DynamicIslandWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 180),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = hosting; window.alphaValue = 0; window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        let scroll = try XCTUnwrap(findScrollView(hosting))
        let editor = try XCTUnwrap(scroll.documentView as? ExtraSpaceTextView)
        window.makeFirstResponder(editor)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "f",
            charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        XCTAssertTrue(editor.performKeyEquivalent(with: event))
        try await waitUntil { scroll.isFindBarVisible }
        XCTAssertFalse(editor.isEditable)
        XCTAssertEqual(editor.string, store.text)
        XCTAssertFalse(store.isDirty)
        XCTAssertFalse(editor.editorUndoManager.canUndo)
        editor.cancelOperation(nil)
        try await waitUntil { !scroll.isFindBarVisible }
        XCTAssertEqual(store.text, "中文 text\nneedle and needle")
    }

    func testTextExportPreservesUnicodeAndFailureDoesNotChangeTheDocument() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = "中文🙂\r\nline\n"
        let url = folder.appendingPathComponent("copy.txt")
        try await ExtraSpaceExport.write(original, to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data(original.utf8))
        do {
            try await ExtraSpaceExport.write(original, to: folder.appendingPathComponent("missing/copy.txt"))
            XCTFail("Missing parent must report failure")
        } catch { XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original) }
    }

    func testPermissionSnapshotRequiresReadAccessAndDistinguishesCameraDenial() {
        var snapshot = FeaturePermissionSnapshot()
        snapshot.events = .writeOnly
        XCTAssertFalse(snapshot.canReadCalendar)
        snapshot.reminders = .fullAccess
        XCTAssertTrue(snapshot.canReadCalendar)
        snapshot.camera = .denied
        XCTAssertNotNil(snapshot.cameraMessage)
        snapshot.camera = .authorized
        XCTAssertNil(snapshot.cameraMessage)
    }

    func testReduceMotionRemovesTheActualCoreAnimationPulse() async throws {
        func root(_ reduced: Bool) -> some View {
            LayerPulse(isActive: true, reduceMotionOverride: reduced) { Text("Working").foregroundStyle(.white) }
                .frame(width: 100, height: 30)
        }
        let hosting = NSHostingView(rootView: root(false))
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting; window.alphaValue = 0; window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        func pulses(_ view: NSView) -> Int {
            (view.layer?.animation(forKey: "atoll.pulse") == nil ? 0 : 1) + view.subviews.reduce(0) { $0 + pulses($1) }
        }
        try await waitUntil { pulses(hosting) > 0 }
        hosting.rootView = root(true)
        try await waitUntil { pulses(hosting) == 0 }
        hosting.rootView = root(false)
        try await waitUntil { pulses(hosting) > 0 }
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AtollNextVersion-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        guard condition() else { throw NSError(domain: "AtollFixtureTimeout", code: 1) }
    }
    private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView($0) }.first
    }
}

@MainActor private final class CalendarFixture: CalendarServiceProviding {
    var queries = 0
    var queryDates: [Date] = []
    var permissionRequests = 0
    var includesReminder = false
    private var reminderCompleted = false
    func requestAccess() async -> Bool { permissionRequests += 1; return false }
    func requestAccess(to type: EKEntityType) async -> Bool { permissionRequests += 1; return false }
    func calendars() async -> [CalendarModel] { [] }
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        queries += 1; queryDates.append(start)
        guard includesReminder else { return [] }
        let calendar = CalendarModel(accountName: "Fixture", id: "fixture-calendar", title: "Fixture",
            color: .blue, isSubscribed: false, isReminder: true)
        return [EventModel(id: "fixture-reminder", start: start, end: end, title: "Fixture",
            location: nil, notes: nil, url: nil, isAllDay: false, type: .reminder(completed: reminderCompleted),
            calendar: calendar, participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil, conferenceURL: nil)]
    }
    func setReminderCompleted(reminderID: String, completed: Bool) async { reminderCompleted = completed }
}
