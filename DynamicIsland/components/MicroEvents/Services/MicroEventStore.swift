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

import Combine
import Foundation

/// The user's own list of Micro Events, stored as one small JSON document.
///
/// Deliberately not `Defaults` (these are content, not settings) and not
/// `EventKit` (writing there would make this another Reminders list and ask for
/// another permission). The file is replaced atomically and no older revision
/// is kept, so a removed item does not linger on disk.
@MainActor
final class MicroEventStore: ObservableObject {
    static let shared = MicroEventStore()

    @Published private(set) var events: [MicroEvent] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var errorMessage: String?

    let fileURL: URL
    private let saveDelay: TimeInterval
    private let persistenceQueue = DispatchQueue(
        label: "app.atoll.micro-events.persistence", qos: .utility)
    private var saveTask: Task<Void, Never>?
    private var pendingWrite: DispatchWorkItem?
    private var editingEvents: [UUID: UUID] = [:]

    private struct Document: Codable {
        var version: Int
        var events: [MicroEvent]
    }

    init(fileURL: URL? = nil, saveDelay: TimeInterval = 0.35) {
        self.fileURL = fileURL ?? AppRuntimeEnvironment.contentURL(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Atoll/MicroEvents/events.json"),
            testPath: "MicroEvents/events.json")
        self.saveDelay = saveDelay
    }

    // MARK: - Loading

    /// Reads the file once. Cheap enough to call from several entry points, and
    /// nothing touches disk until the feature is actually enabled.
    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try Self.decode(data)
            errorMessage = nil
            // Legacy documents have no completion timestamp. A past due date
            // lets startup clear an old completion; a future due date starts
            // the grace period now instead of deleting it immediately.
            var migrated = false
            for index in events.indices where events[index].recurrence == .once
                && events[index].completedKeys.contains(MicroEvent.onceKey)
                && events[index].completedAt == nil {
                events[index].completedAt = min(Date(), events[index].startDate)
                migrated = true
            }
            if migrated { scheduleSave() }
        } catch {
            // Keep the unreadable file next to the new one instead of letting the
            // first edit overwrite a list we could not parse.
            quarantineUnreadableFile()
            errorMessage = String(localized: "Your Micro Events could not be read. The file was kept.")
        }
    }

    private static func decode(_ data: Data) throws -> [MicroEvent] {
        if let document = try? JSONDecoder().decode(Document.self, from: data) {
            return document.events
        }
        // Version 0: a bare array, before the envelope existed.
        return try JSONDecoder().decode([MicroEvent].self, from: data)
    }

    private func quarantineUnreadableFile() {
        let directory = fileURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = directory.appendingPathComponent("events.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }

    // MARK: - Mutations

    func add(_ event: MicroEvent) {
        var normalized = event.normalized()
        normalized.createdAt = Date()
        events.append(normalized)
        scheduleSave()
    }

    func update(_ event: MicroEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index] = event.normalized()
        scheduleSave()
    }

    func remove(id: UUID) {
        guard events.contains(where: { $0.id == id }) else { return }
        events.removeAll { $0.id == id }
        scheduleSave()
    }

    func setCompleted(_ completed: Bool, occurrence: Date, for id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let event = events[index]
        events[index] = completed
            ? event.markingCompleted(occurrence)
            : event.clearingCompletion(occurrence)
        scheduleSave()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }), events[index].isEnabled != enabled else { return }
        events[index].isEnabled = enabled
        scheduleSave()
    }

    func beginEditing(id: UUID, token: UUID) {
        editingEvents[token] = id
    }

    func endEditing(token: UUID, performCleanup: Bool, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        guard editingEvents.removeValue(forKey: token) != nil else { return }
        if performCleanup { cleanupExpiredOccurrences(now: now, calendar: calendar) }
    }

    /// Remove expired one-offs and past completion markers, keeping recurrence rules.
    func cleanupExpiredOccurrences(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let startOfToday = calendar.startOfDay(for: now)
        let todayKey = MicroEvent(title: "", recurrence: .daily).occurrenceKey(for: now, calendar: calendar)
        let protected = Set(editingEvents.values)
        var remaining = events.filter { event in
            guard !protected.contains(event.id) else { return true }
            guard event.recurrence == .once else { return true }
            if event.isCompleted(event.startDate, calendar: calendar) {
                guard let completedAt = event.completedAt else { return true }
                return completedAt >= startOfToday
            }
            return event.startDate >= startOfToday || !event.isEnabled
        }
        for index in remaining.indices where remaining[index].recurrence != .once && !protected.contains(remaining[index].id) {
            remaining[index].completedKeys.removeAll { $0.count == 10 && $0 < todayKey }
        }
        guard remaining != events else { return }
        events = remaining
        saveNow()
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(max(0, self.saveDelay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self.save()
        }
    }

    /// Enqueue the current snapshot without waiting for disk I/O.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    /// Quit and restart wait for the latest snapshot and refuse to discard it on error.
    func saveForTermination() async -> String? {
        guard isLoaded else { return nil }
        saveTask?.cancel()
        saveTask = nil
        pendingWrite?.cancel()
        let snapshot = events
        guard let data = try? JSONEncoder().encode(Document(version: 1, events: snapshot)) else {
            return String(localized: "Your Micro Events could not be saved.")
        }
        let url = fileURL
        let failure: String? = await withCheckedContinuation { continuation in
            persistenceQueue.async {
                continuation.resume(returning: Self.write(data, to: url))
            }
        }
        if let failure {
            errorMessage = failure
            return failure
        }
        guard events == snapshot else {
            return String(localized: "Micro Events changed while saving. Please try Quit or Restart again.")
        }
        return nil
    }

    private func save() {
        let document = Document(version: 1, events: events)
        guard let data = try? JSONEncoder().encode(document) else {
            errorMessage = String(localized: "Your Micro Events could not be saved.")
            return
        }
        let url = fileURL
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let failure = Self.write(data, to: url)
            guard let failure else { return }
            DispatchQueue.main.async {
                self?.errorMessage = failure
            }
        }
        pendingWrite = work
        persistenceQueue.async(execute: work)
    }

    /// Returns an error message, or nil on success.
    private nonisolated static func write(_ data: Data, to url: URL) -> String? {
        do {
            // No previous revision: it would keep deleted and expired records.
            try PrivateContentFile.write(data, to: url, keepingPrevious: false)
            // Earlier builds wrote a second copy that nothing ever read.
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent().appendingPathComponent("events.previous.json"))
            return nil
        } catch {
            return String(localized: "Your Micro Events could not be saved. The previous version is kept.")
        }
    }
}
