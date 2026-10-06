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
    private let persistenceQueue = DispatchQueue(label: "app.atoll.agents.persistence", qos: .utility)
    @Published private(set) var isLoaded = false
    @Published private(set) var persistenceError: String?
    nonisolated static let maximumSnapshotBytes = 8 * 1024 * 1024
    nonisolated static let maximumSessions = 60

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

    init(persistenceURL: URL? = AppRuntimeEnvironment.contentURL(
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Atoll/AgentBridge/sessions.json"),
        testPath: "AgentBridge/sessions.json")) {
        self.persistenceURL = persistenceURL
        if let persistenceURL {
            persistenceQueue.async { [weak self] in
                let result: Result<Snapshot?, Error> = Result {
                    guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return nil }
                    return try JSONDecoder().decode(Snapshot.self, from: PrivateContentFile.read(persistenceURL, limit: Self.maximumSnapshotBytes))
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let snapshot):
                        if let snapshot {
                            let cutoff = Date().addingTimeInterval(-Self.staleSessionInterval)
                            let currentIDs = Set(self.sessions.map(\.id))
                            self.sessions += snapshot.sessions.filter { !currentIDs.contains($0.id) && ($0.lastSeenAt ?? $0.updatedAt) > cutoff }.map { saved in
                                var saved = saved
                                saved.isDisconnected = true
                                saved.canAcceptDirectInput = false
                                saved.finishedAt = nil
                                if saved.state.isWorking || saved.state.needsAttention { saved.state = .idle }
                                return Self.bounded(saved)
                            }
                            self.hiddenIDs.merge(snapshot.hiddenIDs.filter { $0.value > cutoff }) { current, _ in current }
                            self.enforceMemoryBudget()
                        }
                    case .failure(let error): self.persistenceError = error.localizedDescription
                    }
                    self.isLoaded = true
                }
            }
        } else { isLoaded = true }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStaleSessions() }
        }
    }

    deinit {
        pruneTimer?.invalidate()
        highlightExpiry?.cancel()
        saveTask?.cancel()
    }

    func apply(_ event: AgentHookEvent) {
        guard event.sourceID.utf8.count <= 128, event.sessionKey.utf8.count <= 4096 else { return }
        let id = AgentSession.key(sourceID: event.sourceID, sessionKey: event.sessionKey)
        if event.phase == .sessionStarted || event.phase == .promptSubmitted { hiddenIDs[id] = nil }
        guard hiddenIDs[id] == nil else { return }
        let recording = !liveFeedIDs.contains(id)
        let next = sessions.first { $0.id == id }.map { $0.applying(event, recordingMessages: recording) }
            ?? AgentSession.starting(with: event)
        sessions = [Self.bounded(next)] + sessions.filter { $0.id != id }
        enforceMemoryBudget()
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
        enforceMemoryBudget()
        scheduleSave()
    }

    func upsert(_ incoming: AgentSession) {
        let session = Self.bounded(incoming)
        guard session.id.utf8.count <= 4225, session.sourceID.utf8.count <= 128 else { return }
        guard hiddenIDs[session.id] == nil else { return }
        let oldFinishedAt = self.session(id: session.id)?.finishedAt
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if sessions[index] != session { sessions[index] = session }
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        enforceMemoryBudget()
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
        enforceMemoryBudget()
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
        enforceMemoryBudget()
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
        saveTask?.cancel(); saveTask = nil
        guard isLoaded, let persistenceURL else { return }
        let snapshot = Snapshot(sessions: sessions.filter { $0.sessionKey != "screen-question" }, hiddenIDs: hiddenIDs)
        persistenceQueue.async { [weak self] in
            let error = Self.persist(snapshot, to: persistenceURL)
            DispatchQueue.main.async { self?.persistenceError = error }
        }
    }

    /// The only synchronous write barrier: normal application termination.
    func flushPendingSave() {
        saveTask?.cancel(); saveTask = nil
        guard isLoaded, let persistenceURL else { return }
        let snapshot = Snapshot(sessions: sessions.filter { $0.sessionKey != "screen-question" }, hiddenIDs: hiddenIDs)
        persistenceError = persistenceQueue.sync { Self.persist(snapshot, to: persistenceURL) }
    }

    private func enforceMemoryBudget() {
        sessions = Array(sessions.filter { $0.id.utf8.count <= 4225 && $0.sourceID.utf8.count <= 128 }.prefix(Self.maximumSessions))
        hiddenIDs = hiddenIDs.filter { $0.key.utf8.count <= 4225 }
        liveFeedIDs.formIntersection(sessions.map(\.id))
        if hiddenIDs.count > 256 {
            hiddenIDs = Dictionary(uniqueKeysWithValues: hiddenIDs.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
        }
    }

    nonisolated private static func bounded(_ original: AgentSession) -> AgentSession {
        var session = original
        func bounded(_ value: String?, _ bytes: Int = 16_384) -> String? { value.map { Self.prefix($0, bytes: bytes) } }
        session.lastPrompt = bounded(session.lastPrompt)
        session.lastReply = bounded(session.lastReply)
        session.title = bounded(session.title, 1024)
        session.cwd = bounded(session.cwd, 4096)
        session.transcriptPath = bounded(session.transcriptPath, 4096)
        session.model = bounded(session.model, 256)
        session.hostBundleID = bounded(session.hostBundleID, 256)
        session.originator = bounded(session.originator, 256)
        session.sourceKind = bounded(session.sourceKind, 256)
        session.terminalDevice = bounded(session.terminalDevice, 1024)
        session.terminalPane = bounded(session.terminalPane, 1024)
        switch session.state {
        case .tool(let kind, let name, let detail): session.state = .tool(kind, name: Self.prefix(name, bytes: 256), detail: bounded(detail))
        case .failed(let message): session.state = .failed(message: bounded(message))
        case .needsAttention(let message): session.state = .needsAttention(message: bounded(message))
        default: break
        }
        var remaining = 64 * 1024, messages: [AgentMessage] = []
        for message in session.messages.suffix(AgentSession.messageLimit).reversed() where remaining > 0 {
            let text = Self.prefix(message.text, bytes: min(remaining, 16_384))
            remaining -= text.utf8.count
            messages.append(AgentMessage(id: Self.prefix(message.id, bytes: 256), role: message.role, text: text, toolKind: message.toolKind))
        }
        session.messages = messages.reversed()
        return session
    }

    nonisolated private static func prefix(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        // UTF-8 decoding repairs a partial trailing scalar; never keep an
        // unbounded source string as a Substring backed by the original buffer.
        return String(decoding: text.utf8.prefix(max(0, bytes - 3)), as: UTF8.self)
    }

    nonisolated private static func persist(_ snapshot: Snapshot, to url: URL) -> String? {
        do {
            var sessions = snapshot.sessions
            var data = try JSONEncoder().encode(Snapshot(sessions: sessions, hiddenIDs: snapshot.hiddenIDs))
            while data.count > maximumSnapshotBytes, !sessions.isEmpty {
                sessions.removeLast()
                data = try JSONEncoder().encode(Snapshot(sessions: sessions, hiddenIDs: snapshot.hiddenIDs))
            }
            // A failed/oversized old cache is retained once for manual recovery.
            if FileManager.default.fileExists(atPath: url.path),
               (try? PrivateContentFile.read(url, limit: maximumSnapshotBytes)).flatMap({ try? JSONDecoder().decode(Snapshot.self, from: $0) }) == nil {
                let recovery = url.appendingPathExtension("recovery")
                guard !FileManager.default.fileExists(atPath: recovery.path) else { return "The previous session cache needs recovery before it can be replaced." }
                try FileManager.default.moveItem(at: url, to: recovery)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recovery.path)
            }
            try PrivateContentFile.write(data, to: url)
            return nil
        } catch { return error.localizedDescription }
    }
}
