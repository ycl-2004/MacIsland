import AppKit
import Defaults

/// Ask an agent about part of the screen: capture an area, type a question,
/// get the answer in the notch.
///
/// While a question is out it also appears in `AgentSessionStore`, so the closed
/// notch shows it working and flashes when the answer arrives, like any agent.
@MainActor
final class ScreenQuestionManager: ObservableObject {
    static let shared = ScreenQuestionManager()

    enum Phase: Equatable {
        case idle
        case composing
        case asking
        case answered(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var screenshot: NSImage?
    @Published var question = ""
    @Published private(set) var askedQuestion = ""
    /// The backend the current question went to; the picker may change before the next one.
    @Published private(set) var askedBackendID: String?

    private var screenshotURL: URL?
    private var askTask: Task<Void, Never>?
    private static let sessionKey = "screen-question"

    var selectedBackend: AssistantBackend {
        AssistantBackendRegistry.backend(id: Defaults[.screenQuestionBackend]) ?? AssistantBackendRegistry.all[0]
    }

    /// The store entry this question shows up under, so the Agents tab can
    /// draw it as the question card instead of a generic session.
    var sessionID: String? {
        askedBackendID.map { AgentSession.key(sourceID: $0, sessionKey: Self.sessionKey) }
    }

    // MARK: Flow

    /// Lets the user drag out an area. Returns whether a screenshot was taken
    /// (Escape cancels), so the caller can open the notch to the question.
    func capture() async -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            // Shows the system prompt the first time; later the user has to go to System Settings.
            CGRequestScreenCaptureAccess()
            phase = .failed(String(localized: "Allow Atoll under System Settings → Privacy & Security → Screen & System Audio Recording, then try again."))
            return true
        }
        let url = AtollTemporaryFiles.directory(.screenQuestion).appendingPathComponent("\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: drag an area (Space switches to a window); -x: no shutter sound.
        process.arguments = ["-i", "-x", url.path]
        guard (try? await ProcessRunner.run(process)) != nil,
              let image = NSImage(contentsOf: url) else { return false }

        discardScreenshot()
        endSession()
        screenshotURL = url
        screenshot = image
        question = ""
        phase = .composing
        return true
    }

    /// Captures, then opens the notch on the question. Used by the shortcut
    /// and by the button in the Agents tab.
    func captureAndPresent(in vm: DynamicIslandViewModel) {
        Task {
            guard await capture() else { return }
            DynamicIslandViewCoordinator.shared.currentView = .agents
            if vm.notchState == .closed { vm.open() }
        }
    }

    func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .composing, !text.isEmpty, let screenshotURL else { return }
        let backend = selectedBackend
        endSession()
        askedQuestion = text
        askedBackendID = backend.sourceID
        phase = .asking
        record(.promptSubmitted, prompt: text)

        let model = Defaults[.assistantModelOverrides][backend.sourceID]
        askTask = Task { [weak self] in
            do {
                let answer = try await backend.ask(text, about: screenshotURL, model: model)
                self?.finish(with: .answered(answer))
            } catch is CancellationError {
                return
            } catch {
                self?.finish(with: .failed(error.localizedDescription))
            }
        }
    }

    /// Stops a question in flight and goes back to editing it.
    func cancel() {
        askTask?.cancel()
        askTask = nil
        endSession()
        question = askedQuestion
        phase = screenshot == nil ? .idle : .composing
    }

    func dismiss() {
        askTask?.cancel()
        askTask = nil
        endSession()
        discardScreenshot()
        question = ""
        askedQuestion = ""
        phase = .idle
    }

    // MARK: Private

    private func finish(with result: Phase) {
        askTask = nil
        phase = result
        switch result {
        case .answered(let answer): record(.turnFinished, reply: answer)
        case .failed(let message): record(.turnFailed, message: message)
        default: break
        }
    }

    private func record(_ phase: AgentEventPhase, prompt: String? = nil, reply: String? = nil, message: String? = nil) {
        guard let askedBackendID else { return }
        AgentSessionStore.shared.apply(AgentHookEvent(
            sourceID: askedBackendID,
            phase: phase,
            sessionKey: Self.sessionKey,
            cwd: nil,
            prompt: prompt,
            toolName: nil,
            toolKind: nil,
            toolDetail: nil,
            message: message,
            lastReply: reply,
            hostBundleID: nil,
            receivedAt: Date()
        ))
    }

    private func endSession() {
        record(.sessionEnded)
        askedBackendID = nil
    }

    private func discardScreenshot() {
        if let screenshotURL { try? FileManager.default.removeItem(at: screenshotURL) }
        screenshotURL = nil
        screenshot = nil
    }
}
