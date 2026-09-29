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
    @State private var isHoveringAsk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Sessions").font(.notch(.caption, weight: .semibold))
                Text("\(orderedSessions.count)").monospacedDigit().foregroundStyle(.inkTertiary)
                Spacer()
                if let message = conversations.connectionMessage {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.statusAttention).help(message)
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
            .font(.notch(.caption))
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
        return sessions.filter(\.isWaitingOnUser) + sessions.filter { !$0.isWaitingOnUser }
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
                    .font(.notch(.caption, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isHoveringAsk ? Color.inkPrimary : .inkSecondary)
            .frame(width: 104)
            .frame(maxHeight: .infinity)
            .background(isHoveringAsk ? Color.fillCardHover : .fillCard, in: RoundedRectangle(cornerRadius: NotchRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: NotchRadius.card)
                    .strokeBorder(.strokeHairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .contentShape(RoundedRectangle(cornerRadius: NotchRadius.card))
            .onHover { isHoveringAsk = $0 }
            .animation(.notchQuick, value: isHoveringAsk)
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
                .foregroundStyle(.inkTertiary)
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
        .background(.fillCard, in: RoundedRectangle(cornerRadius: NotchRadius.card))
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
                (Text("\(session.source?.displayName ?? session.sourceID) · ")
                    + Text(session.sessionKey.prefix(8)).font(.notch(.micro, design: .monospaced)))
                    .font(.notch(.micro))
                    .foregroundStyle(.inkTertiary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: session.isDisconnected ? "bolt.slash" : session.state.symbolName)
                        .symbolEffect(.pulse, isActive: session.state.isWorking && !session.isDisconnected)
                    Text(session.isDisconnected ? String(localized: "Session ended") : session.state.title)
                        .lineLimit(1)
                }
                .font(.notch(.footnote, weight: .semibold))
                .foregroundStyle(session.isDisconnected ? .inkTertiary : session.state.tint)

                if let detail = session.state.detail {
                    // The command or file, in a well so it reads as code.
                    Text(detail)
                        .font(.notch(.caption, design: .monospaced))
                        .foregroundStyle(.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fillWell, in: RoundedRectangle(cornerRadius: 5))
                }
                if let summary {
                    Text(summary)
                        .font(.notch(.caption))
                        .foregroundStyle(.inkTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Label("Open conversation", systemImage: "bubble.left.and.bubble.right")
                    .font(.notch(.micro, weight: .medium))
                    .foregroundStyle(isHovering ? .inkSecondary : .inkQuaternary)
            }
            .padding(10)
            .frame(width: 210, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(isHovering ? Color.fillCardHover : .fillCard, in: RoundedRectangle(cornerRadius: NotchRadius.card))
            // The agent's colour as a thin edge, so a row of cards can be told
            // apart at a glance without the colour taking over the card.
            .overlay(alignment: .leading) {
                if let source = session.source {
                    Capsule()
                        .fill(source.accentColor.opacity(session.isDisconnected ? 0.35 : 0.85))
                        .frame(width: 2)
                        .padding(.vertical, 12)
                }
            }
            .overlay {
                AttentionOutline(isActive: session.isWaitingOnUser, cornerRadius: NotchRadius.card)
            }
            .contentShape(RoundedRectangle(cornerRadius: NotchRadius.card))
            .onHover { isHovering = $0 }
            .animation(.notchQuick, value: isHovering)
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
                    .font(.notch(.caption, weight: .bold))
                    .foregroundStyle(source.accentColor)
                    .frame(width: 18, height: 18)
                    .background(source.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            }
            Text(session.displayTitle)
                .font(.notch(.body, weight: .semibold))
                .foregroundStyle(.inkPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isReachable {
                Circle().fill(.statusSuccess).frame(width: 6, height: 6)
                    .help(String(localized: "Live: you can message this session from Atoll"))
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.relativeFormatter.localizedString(for: session.updatedAt, relativeTo: context.date))
                    .font(.notch(.micro).monospacedDigit())
                    .foregroundStyle(.inkQuaternary)
            }
        }
    }
}

/// Outlines a card that is waiting on the user. When the wait begins -- or the
/// card first appears already waiting -- the outline pulses three times and
/// then stays lit. It stops on purpose: a question can go unanswered for
/// hours, and a pulse that kept going would run for all of them.
private struct AttentionOutline: View {
    let isActive: Bool
    let cornerRadius: CGFloat
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Color.statusAttention.opacity(isDimmed ? 0.25 : 0.75), lineWidth: 1)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: isActive, initial: true) { _, active in
                guard active else { return }
                // Dim first, then animate back up: an odd repeat count with
                // autoreverse ends on the animated-to value, so the outline
                // finishes lit instead of snapping there afterwards.
                isDimmed = true
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.45).repeatCount(5, autoreverses: true)) {
                        isDimmed = false
                    }
                }
            }
    }
}
