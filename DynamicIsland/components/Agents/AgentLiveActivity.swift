import SwiftUI

/// The closed-notch activity for agents: the agent on the left, what it is
/// doing on the right. Laid out like `DownloadLiveActivity`.
struct AgentLiveActivity: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var store = AgentSessionStore.shared
    @State private var isExpanded = false

    var body: some View {
        let session = store.closedNotchHighlight()
        let sideWidth = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: 0) {
            Color.clear
                .background {
                    if isExpanded, let source = session?.source {
                        Image(systemName: source.symbolName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(source.accentColor)
                            .frame(width: sideWidth, height: sideWidth)
                            .background(source.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: isExpanded ? vm.effectiveClosedNotchHeight - 12 : 0, height: sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 20)

            Color.clear
                .background {
                    if isExpanded, let session {
                        HStack(spacing: 4) {
                            if store.activeSessionCount > 1 {
                                Text("\(store.activeSessionCount)")
                                    .font(.notch(.caption, weight: .semibold).monospacedDigit())
                                    // Not `.secondary`: the closed notch is not dark-schemed, so it renders near-black.
                                    .foregroundStyle(.inkSecondary)
                            }
                            statusIndicator(for: session.state)
                        }
                        .padding(.trailing, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: isExpanded ? max(44, vm.effectiveClosedNotchHeight) : 0, height: sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: session?.state)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let session else { return }
            AgentConversationService.shared.requestedSessionID = session.id
            DynamicIslandViewCoordinator.shared.currentView = .agents
            vm.open()
        }
        .accessibilityLabel("Open agent conversation")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { isExpanded = true }
        }
    }

    /// What the agent is doing, as a glyph: it pulses while the agent works
    /// and bounces once when the state settles. A system `ProgressView` is
    /// avoided on purpose — it renders dark on the notch's black. The pulse
    /// runs for as long as the agent works, often hours, so it is a Core
    /// Animation one (`LayerPulse`) rather than `symbolEffect(.pulse)`.
    private func statusIndicator(for state: AgentState) -> some View {
        LayerPulse(isActive: state.isWorking && !reduceMotion) {
            Image(systemName: state.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(state.tint)
                .symbolEffect(.bounce, value: state.isWorking ? nil : state)
                .symbolEffectsRemoved(reduceMotion)
        }
    }
}
