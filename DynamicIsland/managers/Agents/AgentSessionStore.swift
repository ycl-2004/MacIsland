import Foundation
import Combine

/// Every agent session Atoll has heard from, newest first.
@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    /// How long a finished turn keeps the closed notch lit.
    static let finishedHighlightDuration: TimeInterval = 6
    /// Not every agent reports that a session ended, so a session with no sign
    /// of life for this long leaves the notch.
    static let staleSessionInterval: TimeInterval = 30 * 60

    @Published private(set) var sessions: [AgentSession] = []

    private var pruneTimer: Timer?
    private var highlightExpiry: Task<Void, Never>?
    /// Cards the user removed, and when. A removed session only comes back by
    /// starting a new turn, so each entry is kept as long as anything else
    /// could still bring the card back: `staleSessionInterval`.
    private var hiddenIDs: [String: Date] = [:]
    /// Sessions whose conversation arrives from a live feed rather than hooks.
    private var liveFeedIDs: Set<String> = []
    private let persistenceURL: URL?
    private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        let sessions: [AgentSession]
        let hiddenIDs: [String: Date]

        init(sessions: [AgentSession], hiddenIDs: [String: Date]) {
            self.sessions = sessions
            self.hiddenIDs = hiddenIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessions = try container.decode([AgentSession].self, forKey: .sessions)
            // Earlier versions saved only the ids; they count as removed now.
            if let dated = try? container.decode([String: Date].self, forKey: .hiddenIDs) {
                hiddenIDs = dated
            } else {
                let ids = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenIDs) ?? []
                hiddenIDs = Dictionary(uniqueKeysWithValues: ids.map { ($0, Date()) })
            }
        }
    }

    init(persistenceURL: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Atoll/AgentBridge/sessions.json")) {
        self.persistenceURL = persistenceURL
        if let persistenceURL, let data = try? Data(contentsOf: persistenceURL),
           data.count <= 8 * 1024 * 1024, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.staleSessionInterval)
            sessions = snapshot.sessions.filter { ($0.lastSeenAt ?? $0.updatedAt) > cutoff }.map { saved in
                var saved = saved
                saved.isDisconnected = true
                saved.canAcceptDirectInput = false
                saved.finishedAt = nil
                if saved.state.isWorking || saved.state.needsAttention { saved.state = .idle }
                return saved
            }
            hiddenIDs = snapshot.hiddenIDs
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStaleSessions() }
        }
    }

    func apply(_ event: AgentHookEvent) {
        let id = AgentSession.key(sourceID: event.sourceID, sessionKey: event.sessionKey)
        if event.phase == .sessionStarted || event.phase == .promptSubmitted { hiddenIDs[id] = nil }
        guard hiddenIDs[id] == nil else { return }
        let recording = !liveFeedIDs.contains(id)
        let next = sessions.first { $0.id == id }.map { $0.applying(event, recordingMessages: recording) }
            ?? AgentSession.starting(with: event)
        sessions = [next] + sessions.filter { $0.id != id }
        scheduleSave()

        if event.phase == .turnFinished || event.phase == .turnFailed {
            scheduleHighlightExpiry()
        }
    }

    func remove(_ session: AgentSession) {
        remove([session])
    }

    /// Removes these cards in one change, so the notch redraws once.
    func remove(_ removed: [AgentSession], now: Date = Date()) {
        let ids = Set(removed.map(\.id))
        guard !ids.isEmpty else { return }
        for id in ids { hiddenIDs[id] = now }
        liveFeedIDs.subtract(ids)
        sessions.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func upsert(_ session: AgentSession) {
        guard hiddenIDs[session.id] == nil else { return }
        let oldFinishedAt = self.session(id: session.id)?.finishedAt
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if sessions[index] != session { sessions[index] = session }
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        scheduleSave()
        if session.finishedAt != nil, oldFinishedAt != session.finishedAt { scheduleHighlightExpiry() }
    }

    func session(id: String) -> AgentSession? { sessions.first { $0.id == id } }

    func hasLiveFeed(_ id: String) -> Bool { liveFeedIDs.contains(id) }

    /// The user removed this session's card; it stays gone until it starts a new turn.
    func isHidden(_ id: String) -> Bool { hiddenIDs[id] != nil }

    func setLiveFeed(_ id: String, _ live: Bool) {
        if live { liveFeedIDs.insert(id) } else { liveFeedIDs.remove(id) }
    }

    func removeAll() {
        sessions.removeAll()
        liveFeedIDs.removeAll()
        scheduleSave()
    }

    // MARK: Closed notch

    /// The one session worth showing while the notch is closed: anything
    /// waiting on the user first, then a turn that just finished, then work
    /// in progress.
    func closedNotchHighlight(now: Date = Date()) -> AgentSession? {
        if let waiting = sessions.first(where: { $0.isTerminalSession && $0.state.needsAttention && !$0.isDisconnected }) {
            return waiting
        }
        if let finished = sessions.first(where: { session in
            guard session.isTerminalSession, !session.isDisconnected, let finishedAt = session.finishedAt else { return false }
            return now.timeIntervalSince(finishedAt) < Self.finishedHighlightDuration
        }) {
            return finished
        }
        return sessions.first { $0.isTerminalSession && $0.state.isWorking && !$0.isDisconnected }
    }

    var activeSessionCount: Int {
        sessions.filter { $0.isTerminalSession && !$0.isDisconnected && ($0.state.isWorking || $0.state.needsAttention) }.count
    }

    /// Re-publishes once the "finished" flash is over, so the closed notch drops it.
    private func scheduleHighlightExpiry() {
        highlightExpiry?.cancel()
        highlightExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.finishedHighlightDuration))
            guard !Task.isCancelled else { return }
            self?.objectWillChange.send()
        }
    }

    func pruneStaleSessions(now: Date = Date()) {
        let fresh = sessions.filter { now.timeIntervalSince($0.lastSeenAt ?? $0.updatedAt) < Self.staleSessionInterval }
        // By then nothing but a new turn brings a removed card back, and a new turn would anyway.
        let expired = hiddenIDs.filter { now.timeIntervalSince($0.value) >= Self.staleSessionInterval }.map(\.key)
        guard fresh.count != sessions.count || !expired.isEmpty else { return }
        if fresh.count != sessions.count {
            sessions = fresh
            liveFeedIDs.formIntersection(fresh.map(\.id))
        }
        for id in expired { hiddenIDs[id] = nil }
        scheduleSave()
    }

    /// The connection carrying live feeds closed. Terminals may still be open,
    /// so sessions stay; they only stop accepting messages until it returns.
    func dropLiveFeeds() {
        for index in sessions.indices where liveFeedIDs.contains(sessions[index].id) {
            sessions[index].canAcceptDirectInput = false
        }
        liveFeedIDs.removeAll()
    }

    private func scheduleSave() {
        guard persistenceURL != nil, saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.save()
        }
    }

    func save() {
        guard let persistenceURL else { return }
        // Screen questions remain ephemeral. Keep only bounded public history.
        let snapshot = Snapshot(sessions: Array(sessions.filter { $0.sessionKey != "screen-question" }.prefix(60)), hiddenIDs: hiddenIDs)
        do {
            let directory = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: persistenceURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
        } catch {
            // A failed cache write must not interrupt a live agent.
        }
    }
}
