import AppKit

/// A single save gate shared by Quit and Restart. Timeout releases the UI but
/// keeps ownership of slow I/O, so repeated attempts cannot pile up more writes.
@MainActor
final class TerminationSaveGate {
    private(set) var isSaving = false
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((String?) -> Void)?
    private let save: () async -> String?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 10, save: @escaping () async -> String?) {
        self.timeout = timeout
        self.save = save
    }

    func prepare(completion: @escaping (String?) -> Void) {
        guard !isSaving else { completion("A previous save is still finishing. Your content is still open."); return }
        isSaving = true
        self.completion = completion
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            self?.finish("Saving is taking too long. Your content is still open; try again when storage is available.")
        }
        Task {
            let error = await save()
            isSaving = false
            timeoutTask?.cancel(); timeoutTask = nil
            finish(error)
        }
    }

    private func finish(_ error: String?) {
        let callback = completion
        completion = nil
        callback?(error)
    }
}

@MainActor
final class AppTerminationCoordinator {
    static let shared = AppTerminationCoordinator()
    private var prepared = false
    private var restartPending = false
    private lazy var gate = TerminationSaveGate {
        // A LibreOffice or FFmpeg child would otherwise keep running after quit.
        await FileConvertModel.shared.stopForTermination()
        return await Self.saveContent(extraSpace: .shared, shelf: .shared, sessions: .shared,
                                      conversation: .shared, timer: .shared)
    }

    static func saveContent(extraSpace: ExtraSpaceStore, shelf: ShelfStateViewModel,
                            sessions: AgentSessionStore, conversation: AgentConversationService,
                            timer: TimerManager) async -> String? {
        // All five stores are instantiated before the first await. Initial
        // restoration is not a user edit; snapshot only after it has settled.
        await extraSpace.awaitInitialLoad()
        await shelf.awaitInitialLoad()
        await sessions.awaitInitialLoad()
        await conversation.awaitInitialLoad()
        await timer.awaitInitialRecovery()
        let text = extraSpace.text
        let shelfItems = shelf.items
        let drafts = conversation.drafts
        let timerRevision = timer.recoveryRevision
        var errors: [String] = []
        if let error = await extraSpace.saveForTermination() { errors.append(error) }
        if let error = await shelf.saveForTermination() { errors.append(error) }
        if let error = await sessions.saveForTermination() { errors.append(error) }
        if let error = await conversation.saveForTermination() { errors.append(error) }
        if let error = await timer.saveForTermination() { errors.append(error) }
        if text != extraSpace.text || shelfItems != shelf.items
            || drafts != conversation.drafts || timerRevision != timer.recoveryRevision {
            errors.append("Content changed while saving. Please try Quit or Restart again.")
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    // https://developer.apple.com/documentation/appkit/nsapplication/terminatereply
    func shouldTerminate() -> NSApplication.TerminateReply {
        if prepared { return .terminateNow }
        guard !restartPending, !gate.isSaving else { return .terminateCancel }
        prepare { [weak self] error in
            guard let self else { return }
            self.prepared = error == nil
            NSApp.reply(toApplicationShouldTerminate: error == nil)
            if let error { self.showFailure(error) }
        }
        return .terminateLater
    }

    func restart() {
        guard !restartPending, !gate.isSaving else { return }
        restartPending = true
        prepare { [weak self] error in
            guard let self else { return }
            if let error {
                self.restartPending = false
                self.showFailure(error)
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
                Task { @MainActor in
                    self.restartPending = false
                    guard error == nil, let app, !app.isTerminated,
                          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                        ExtraSpaceStore.shared.isRelaunching = false
                        self.showFailure("The replacement app did not start. Your current session remains open.")
                        return
                    }
                    self.prepared = true
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func prepare(completion: @escaping (String?) -> Void) {
        for window in NSApp.windows {
            if let editor = window.firstResponder as? ExtraSpaceTextView {
                if editor.hasMarkedText() { editor.unmarkText(); editor.didChangeText() }
                window.makeFirstResponder(nil)
            }
        }
        ExtraSpaceStore.shared.isRelaunching = true
        gate.prepare { error in
            if error != nil { ExtraSpaceStore.shared.isRelaunching = false }
            completion(error)
        }
    }

    private func showFailure(_ error: String) {
        Logger.log("Exit cancelled because saving or restart failed", category: .error)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Atoll is keeping your content open"
        alert.informativeText = error + "\nRetry Quit or Restart after resolving the problem. You can export Extra Space and unsent Agent drafts now."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Export Unsaved Text…")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Atoll Recovery.json"
        let snapshot = ["extraSpace": ExtraSpaceStore.shared.text, "agentDrafts": AgentConversationService.shared.drafts] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await ExtraSpaceExport.write(text, to: url) }
                catch { self.showFailure("Export failed. The text is still open.") }
            }
        }
    }
}
