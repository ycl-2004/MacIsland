import SwiftUI

/// The Agents tab: the screen question (or the button to start one), then one
/// card per session Atoll has heard from.
struct NotchAgentsView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var store = AgentSessionStore.shared
    @ObservedObject private var questions = ScreenQuestionManager.shared
    @ObservedObject private var conversations = AgentConversationService.shared
    @State private var selectedID: String?
    @State private var autoCloseToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Sessions").font(.system(size: 11, weight: .semibold))
                Text("\(orderedSessions.count)").foregroundStyle(.secondary)
                Spacer()
                if let message = conversations.connectionMessage {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help(message)
                }
                Button { store.remove(endedSessions) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(endedSessions.isEmpty)
                .help(String(localized: "Remove ended sessions"))
                .accessibilityLabel("Remove ended sessions")
                Button { Task { await conversations.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh agent sessions")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    if questions.phase == .idle {
                        askTile
                    } else {
                        ScreenQuestionCard()
                    }
                    if orderedSessions.isEmpty {
                        emptyHint
                    } else {
                        ForEach(orderedSessions) { session in
                            AgentSessionCard(session: session,
                                             liveText: conversations.streaming[session.id],
                                             isReachable: conversations.canSend(session)) {
                                selectedID = session.id
                                conversations.select(session.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .popover(isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } }), arrowEdge: .top) {
            if let selectedID {
                AgentConversationView(sessionID: selectedID, dismiss: { self.selectedID = nil })
            }
        }
        .onChange(of: selectedID) { _, id in
            vm.setAutoCloseSuppression(id != nil, token: autoCloseToken)
            if id == nil { conversations.selectedID = nil }
        }
        .onDisappear {
            selectedID = nil
            conversations.selectedID = nil
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
        }
    }

    /// Sessions waiting on the user first, the rest newest first. The screen
    /// question has its own card, so its session is left out here.
    private var orderedSessions: [AgentSession] {
        let sessions = store.sessions.filter { $0.id != questions.sessionID && $0.isTerminalSession }
        return sessions.filter { $0.state.needsAttention && !$0.isDisconnected }
            + sessions.filter { !$0.state.needsAttention || $0.isDisconnected }
    }

    /// Cards of sessions that ended. Removing one hides it like "Remove from
    /// Notch", until that session starts a new turn.
    private var endedSessions: [AgentSession] {
        orderedSessions.filter(\.isDisconnected)
    }

    private var askTile: some View {
        Button {
            questions.captureAndPresent(in: vm)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .medium))
                Text("Ask about the screen")
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 104)
            .frame(maxHeight: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(String(localized: "Drag out an area of the screen, then ask Claude Code, Codex or Antigravity about it."))
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No agent sessions yet")
                .font(.headline)
            Text(conversations.connectionMessage ?? String(localized: "Start Claude Code, Codex or Antigravity in a terminal and its session appears here. Connect each agent once in Settings → Agents."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AgentSessionCard: View {
    let session: AgentSession
    /// What the agent is writing right now, straight from a live session.
    let liveText: String?
    /// A message typed in Atoll reaches this session.
    let isReachable: Bool
    let open: () -> Void
    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// What the agent is writing now, its last reply once it is done, or else
    /// what it was last asked.
    private var summary: String? {
        if let live = liveText?.nonBlank {
            return live.split(whereSeparator: \.isNewline).suffix(2).joined(separator: "\n")
        }
        return (session.state == .finished ? (session.lastReply ?? session.lastPrompt) : session.lastPrompt)?.nonBlank
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Text("\(session.source?.displayName ?? session.sourceID) · \(session.sessionKey.prefix(8))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: session.isDisconnected ? "bolt.slash" : session.state.symbolName)
                        .symbolEffect(.pulse, isActive: session.state.isWorking && !session.isDisconnected)
                    Text(session.isDisconnected ? String(localized: "Session ended") : session.state.title)
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(session.state.tint)

                if let detail = session.state.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let summary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Label("Open conversation", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(width: 210, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(isHovering ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if session.state.needsAttention {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { isHovering = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open conversation: \(session.displayTitle)")
        .help(session.cwd ?? "")
        .contextMenu {
            Button("Remove from Notch") { AgentSessionStore.shared.remove(session) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let source = session.source {
                Image(systemName: source.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(source.accentColor)
                    .frame(width: 18, height: 18)
                    .background(source.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(session.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if isReachable {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .help(String(localized: "Live: you can message this session from Atoll"))
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: context.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
