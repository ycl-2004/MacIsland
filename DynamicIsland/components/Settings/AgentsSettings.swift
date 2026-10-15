import SwiftUI
import Defaults

struct AgentsSettingsView: View {
    @Default(.enableAgentsFeature) private var enableAgentsFeature
    @Default(.agentClaudeExtendedLifecycle) private var claudeExtendedLifecycle
    @Default(.agentCodexExtendedLifecycle) private var codexExtendedLifecycle
    @Default(.screenQuestionBackend) private var screenQuestionBackend
    @Default(.assistantModelOverrides) private var modelOverrides

    private func highlightID(_ title: String) -> String {
        "agents-\(title)"
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAgentsFeature) {
                    Text("Enable agent tracking")
                }
                .settingsHighlight(id: highlightID("Enable agent tracking"))

                Defaults.Toggle(key: .showAgentActivityInClosedNotch) {
                    Text("Show agent activity in the closed notch")
                }
                .disabled(!enableAgentsFeature)
                .settingsHighlight(id: highlightID("Show agent activity in the closed notch"))
            } header: {
                SettingsInfoLabel("Agents", info: "Active terminal sessions of connected agents appear in the notch. Open a card to follow the conversation. Everything stays on this Mac.")
            }

            Section {
                Defaults.Toggle("Claude Code: tool failures and API failures", key: .agentClaudeExtendedLifecycle)
                Defaults.Toggle("Codex: tool returns and interruptions", key: .agentCodexExtendedLifecycle)
            } header: {
                SettingsInfoLabel("Extended lifecycle hooks", info: "Turn on only if your installed agent version supports these hooks, then click Update below. Agent files change only when you install or update hooks.")
            }

            Section {
                ForEach(AgentSourceRegistry.all, id: \.id) { source in
                    AgentSourceRow(source: source).id(source.id + "-\(claudeExtendedLifecycle)-\(codexExtendedLifecycle)")
                }
            } header: {
                SettingsInfoLabel("Connected agents", info: "Install adds Atoll's hooks to the agent's config and keeps your other hooks. The previous file is saved next to it with an .atoll-backup extension. Pi and OpenCode get a plugin file instead, which Remove deletes. The hooks only report activity; they never approve, block or change a tool call.")
            }

            Section {
                AgentConnectionStatusView()
            } header: {
                SettingsInfoLabel("Replying from Atoll", info: "Codex takes messages in terminals that use its shared service; a terminal started with --no-daemon is read-only. Claude Code takes them while it waits for you, and Antigravity while it works. Pi, OpenCode and Grok Build take them in terminals Atoll can type into.")
            }

            Section {
                Picker("Ask", selection: $screenQuestionBackend) {
                    ForEach(AssistantBackendRegistry.all, id: \.sourceID) { backend in
                        Text(backend.source?.displayName ?? backend.sourceID).tag(backend.sourceID)
                    }
                }
                .settingsHighlight(id: highlightID("Screen question agent"))
                ForEach(AssistantBackendRegistry.all, id: \.sourceID) { backend in
                    TextField(backend.source?.displayName ?? backend.sourceID, text: modelBinding(for: backend.sourceID), prompt: Text("Default model"))
                }
            } header: {
                SettingsInfoLabel("Screen questions", info: "Questions run the agent's own command-line tool on this Mac with your sign-in, so no API key is needed. Leave the model empty to use the tool's default.")
            }
            .disabled(!enableAgentsFeature)
        }
        .navigationTitle("Agents")
    }

    private func modelBinding(for sourceID: String) -> Binding<String> {
        Binding(
            get: { modelOverrides[sourceID] ?? "" },
            set: { modelOverrides[sourceID] = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }
}

private struct AgentConnectionStatusView: View {
    @ObservedObject private var service = AgentConversationService.shared
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(service.isLive ? "Connected to Codex's shared service" : "Codex's shared service is not running")
                if let message = service.connectionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Refresh") { Task { await service.refresh() } }
        }
    }
}

private struct AgentSourceRow: View {
    let source: AgentSource
    @State private var isInstalled = false
    @State private var isOutdated = false
    @State private var errorMessage: String?

    private var status: String {
        if isInstalled { return String(localized: "Hooks installed") }
        if isOutdated { return String(localized: "Hook update available") }
        if !source.isCLIAvailable { return String(localized: "Not found on this Mac") }
        return String(localized: "Not connected")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: source.symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(source.accentColor)
                    .frame(width: 22, height: 22)
                    .background(source.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.displayName)
                    HStack(spacing: 4) {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(isInstalled ? .green : .secondary)
                        if isInstalled, let note = source.installNote {
                            SettingsInfoButton(verbatim: note)
                                .font(.caption)
                        }
                    }
                }
                Spacer()
                Button(isInstalled ? "Remove" : isOutdated ? "Update" : "Install") { toggle() }
                    // Removing stays possible even after the CLI is gone.
                    .disabled(!isInstalled && !source.isCLIAvailable)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .onAppear(perform: refresh)
    }

    private func toggle() {
        do {
            if isInstalled {
                try AgentBridge.shared.removeHooks(for: source)
            } else {
                try AgentBridge.shared.installHooks(for: source)
            }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Could not update \(source.installation.fileURL.path): \(error.localizedDescription)")
        }
        refresh()
    }

    private func refresh() {
        isInstalled = AgentBridge.shared.hooksInstalled(for: source)
        isOutdated = AgentBridge.shared.hooksOutdated(for: source)
    }
}
