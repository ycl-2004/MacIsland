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
                Text("Agents")
            } footer: {
                Text("Terminal sessions of each connected agent appear in the notch while they are active. Open a card to follow the conversation as it runs. Connections stay on this Mac.")
            }

            Section {
                Defaults.Toggle("Claude Code: tool failures and API failures", key: .agentClaudeExtendedLifecycle)
                Defaults.Toggle("Codex: tool returns and interruptions", key: .agentCodexExtendedLifecycle)
            } header: {
                Text("Extended lifecycle hooks")
            } footer: {
                Text("Enable only when your installed agent supports these hooks, then use Update below. Older versions can reject unknown hook names. Turning this off lets Update restore the compatible profile. This choice does not change agent files until you install or update hooks.")
            }

            Section {
                ForEach(AgentSourceRegistry.all, id: \.id) { source in
                    AgentSourceRow(source: source).id(source.id + "-\(claudeExtendedLifecycle)-\(codexExtendedLifecycle)")
                }
            } header: {
                Text("Connected agents")
            } footer: {
                Text("Installing adds Atoll's hooks to the agent's own config and leaves your other hooks alone; the file as it was before is kept beside it with an .atoll-backup extension. Agents that load plugins instead (Pi, OpenCode) get a plugin file of Atoll's own, which Remove deletes. Atoll's hooks only report what the agent does and never approve, block or change a tool call.")
            }

            Section {
                AgentConnectionStatusView()
            } header: {
                Text("Replying from Atoll")
            } footer: {
                Text("Codex takes messages from Atoll in terminals that run on its shared service; a terminal started with --no-daemon is read-only here. Claude Code takes them while it waits for you, and Antigravity while it works, through Atoll's hooks. Pi, OpenCode and Grok Build take them in terminals Atoll can type into.")
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
                Text("Screen questions")
            } footer: {
                Text("Questions run the agent's own CLI on this Mac, signed in as you, so no API key is needed. A model name is passed to the CLI as-is; leave it empty to use the CLI's default.")
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
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(isInstalled ? .green : .secondary)
                }
                Spacer()
                Button(isInstalled ? "Remove" : isOutdated ? "Update" : "Install") { toggle() }
                    // Removing stays possible even after the CLI is gone.
                    .disabled(!isInstalled && !source.isCLIAvailable)
            }
            if isInstalled, let note = source.installNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
