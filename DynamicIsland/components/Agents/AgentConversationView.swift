import SwiftUI

/// A keyboard-capable popover keeps the conversation attached to its card
/// without squeezing the transcript into the notch's compact height.
/// https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)
struct AgentConversationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sessionID: String
    let dismiss: () -> Void
    @ObservedObject private var store: AgentSessionStore
    @ObservedObject private var service: AgentConversationService
    @FocusState private var composerFocused: Bool
    @State private var hostError: String?

    init(sessionID: String, store: AgentSessionStore? = nil,
         service: AgentConversationService? = nil, dismiss: @escaping () -> Void) {
        self.sessionID = sessionID
        self.store = store ?? .shared
        self.service = service ?? .shared
        self.dismiss = dismiss
    }

    private var session: AgentSession? { store.session(id: sessionID) }
    private var draft: Binding<String> {
        Binding(get: { service.drafts[sessionID] ?? "" }, set: { service.setDraft($0, for: sessionID) })
    }
    private var isSending: Bool { service.sending.contains(sessionID) }
    private var isUncertain: Bool { service.uncertainIDs.contains(sessionID) && !isSending }
    private var streamingText: String? { service.streaming[sessionID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session {
                header(session)
                connectionNote(session)
                Divider()
                transcript(session)
                ForEach(service.approvals.filter { $0.sessionID == sessionID }) { approval in
                    approvalView(approval)
                }
                if let error = service.errors[sessionID] ?? hostError {
                    Text(error).font(.caption).foregroundStyle(.statusAttention).textSelection(.enabled)
                } else if let notice = service.notices[sessionID] {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                if isUncertain {
                    Button("I checked the conversation in the terminal") { service.acknowledgeUncertainDelivery(id: sessionID) }
                        .controlSize(.small)
                }
                Divider()
                composer(session)
            } else {
                ContentUnavailableView("Session removed", systemImage: "bubble.left", description: Text("Choose another session from the Agents tab."))
                Button("Close", action: dismiss)
            }
        }
        .padding(16)
        .frame(width: 580, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        .onAppear {
            NSApp.activate()
            DispatchQueue.main.async { composerFocused = true }
        }
        .onExitCommand(perform: dismiss)
    }

    private func header(_ session: AgentSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: session.source?.symbolName ?? "sparkles")
                .font(.title2).foregroundStyle(session.source?.accentColor ?? .white)
                .frame(width: 32, height: 32)
                .background(.fillCard, in: RoundedRectangle(cornerRadius: NotchRadius.control))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle).font(.headline).lineLimit(1)
                Text([session.source?.displayName, session.model, session.projectName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Label(session.statusTitle,
                  systemImage: session.statusSymbol)
                .font(.caption).foregroundStyle(session.statusTint)
                .symbolEffect(.pulse, isActive: !reduceMotion && session.state.isWorking && !session.isDisconnected && session.statusUncertain != true)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Close conversation")
        }
    }

    /// Says plainly whether a message typed here can reach the session, and when it will.
    private func connectionNote(_ session: AgentSession) -> some View {
        let route = service.route(for: session)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(route != nil ? Color.statusSuccess : Color.secondary.opacity(0.6)).frame(width: 6, height: 6)
            Text(connectionText(session, route: route)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connectionText(_ session: AgentSession, route: AgentSendRoute?) -> String {
        let name = session.source?.displayName ?? String(localized: "The agent")
        if session.isDisconnected {
            return String(localized: "This session has ended. Its conversation stays readable here.")
        }
        if session.statusUncertain == true {
            return String(localized: "The connection or event stream was interrupted. Check this session in its terminal before sending; the last observed status is not confirmed.")
        }
        switch route {
        case .sharedService:
            return String(localized: "Live: messages you send here go straight into this session, and its terminal shows them.")
        case .terminal(let terminal):
            return String(localized: "Messages you send here are typed into this session's \(terminal) tab and submitted, as if you typed them there, after anything already typed in it.")
        case .wakeWhenIdle:
            return String(localized: "\(name) is waiting for you. A message you send here continues this session, and its terminal shows it.")
        case .injectWhileWorking:
            return String(localized: "\(name) is working. A message you send here joins its next step.")
        case nil:
            break
        }
        if session.state.needsAttention {
            return String(localized: "\(name) is waiting for your answer in the terminal. Answer it there; Atoll does not type into that prompt.")
        }
        if let terminal = service.terminalName(for: session), session.terminalPane == nil {
            return String(localized: "Atoll finds this session's \(terminal) tab after your next message there. Then you can reply here.")
        }
        switch session.source?.replyDelivery {
        case .sharedService:
            return service.connectionMessage ?? String(localized: "Read-only: this terminal runs Codex without its shared service (for example with --no-daemon), so only the terminal can send to it. The conversation still updates as it runs.")
        case .wakeWhenIdle:
            return session.state.isWorking
                ? String(localized: "\(name) is working. You can reply here once it is waiting for you.")
                : String(localized: "Replying from Atoll works in sessions started after Atoll's hooks were installed or updated (Settings → Agents), from the end of their next turn.")
        case .injectWhileWorking:
            return String(localized: "\(name) takes messages from Atoll only while it works. To start a new turn, type in the terminal.")
        case nil:
            return String(localized: "Read-only: this conversation updates as the terminal runs. Type in the terminal to reply.")
        }
    }

    private func transcript(_ session: AgentSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty, streamingText == nil {
                        Text("The conversation appears here as the session runs.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(session.messages) { message in
                        AgentMessageRow(message: message, agentName: session.source?.displayName ?? "Agent")
                            .equatable()
                    }
                    if let streamingText {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(session.source?.displayName ?? "Agent", systemImage: "ellipsis")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                            if !streamingText.isEmpty {
                                Text(AgentMessageRow.markdown(streamingText)).font(.notch(.body)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .background(.fillCard, in: RoundedRectangle(cornerRadius: 10))
                    } else if session.state.isWorking, !session.isDisconnected {
                        Label(session.state.title, systemImage: session.state.symbolName)
                            .font(.caption).foregroundStyle(.secondary)
                            .symbolEffect(.pulse, isActive: !reduceMotion)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
            }
            .onChange(of: session.messages.last?.id, initial: true) { _, _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .onChange(of: streamingText) { _, _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }

    private func composer(_ session: AgentSession) -> some View {
        let reachable = service.canSend(session)
        return VStack(alignment: .leading, spacing: 8) {
            if reachable {
                TextField("Message this session…", text: draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...4).font(.notch(.body))
                    .focused($composerFocused)
                    .onSubmit { service.send(id: sessionID) }
                    .padding(10)
                    .background(.fillCard, in: RoundedRectangle(cornerRadius: NotchRadius.control))
                    .accessibilityLabel("Message this session")
            }
            HStack {
                Button("Open Terminal") { openHost(session) }
                if session.sourceID == "codex", !reachable {
                    Button("Copy Resume Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("codex resume \(session.sessionKey)", forType: .string)
                    }
                    .help(String(localized: "Run it in a terminal to continue this session there."))
                }
                if service.canInterrupt(session) {
                    Button("Stop") { service.interrupt(id: sessionID) }
                        .help(String(localized: "Stop the running turn, like Esc in the terminal."))
                }
                Spacer()
                if reachable {
                    if draft.wrappedValue.count > AgentSession.messageCharacterLimit {
                        Text("Message is too long").font(.caption).foregroundStyle(.statusAttention)
                    }
                    if isSending { ProgressView().controlSize(.small) }
                    Button(isSending ? "Sending…" : "Send") { service.send(id: sessionID) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(isSending || isUncertain
                                  || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || draft.wrappedValue.count > AgentSession.messageCharacterLimit)
                }
            }
            .controlSize(.small)
        }
    }

    private func approvalView(_ approval: AgentApproval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(approval.title).font(.callout.weight(.semibold))
            ScrollView { Text(approval.detail).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 70)
            HStack {
                Spacer()
                Button("Deny") { service.answerApproval(approval, allow: false) }
                Button("Allow once") { service.answerApproval(approval, allow: true) }
            }.controlSize(.small)
        }
        .padding(10)
        .background(Color.statusAttention.opacity(0.12), in: RoundedRectangle(cornerRadius: NotchRadius.control))
    }

    private func openHost(_ session: AgentSession) {
        Task {
            switch await service.openTerminal(session) {
            case .pane:
                hostError = nil
            case .app(let problem):
                hostError = problem
            case .unavailable:
                hostError = session.sourceID == "codex"
                    ? String(localized: "The original terminal is not identified. In a terminal, continue this session with: codex resume \(session.sessionKey)")
                    : String(localized: "The original terminal is not identified or no longer running. Reopen it to continue this session.")
            }
        }
    }

}

/// One line of the conversation. Equatable, so a refresh (every second while
/// the agent writes) redraws only lines whose text changed instead of parsing
/// the Markdown of every line again.
private struct AgentMessageRow: View, Equatable {
    let message: AgentMessage
    let agentName: String

    var body: some View {
        switch message.role {
        case .activity:
            // One line per tool call, like the terminal's "• Ran git status".
            let kind = message.toolKind ?? .other
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: kind.symbolName).frame(width: 14)
                (Text(kind.activityVerb + " ") + Text(message.text).font(.notch(.caption, design: .monospaced)))
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.notch(.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .help(message.text)
        case .user, .assistant:
            let isUser = message.role == .user
            VStack(alignment: .leading, spacing: 5) {
                Text(isUser ? String(localized: "You") : agentName)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(Self.markdown(message.text)).font(.notch(.body)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(isUser ? Color.fillWell : .fillCard, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
