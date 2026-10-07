import Foundation
import SwiftUI

struct PiAgentSource: PluginAgentSource {
    let id = "pi"
    let displayName = "Pi"
    let symbolName = "pi"
    let accentColor = Color(red: 0.36, green: 0.80, blue: 0.62)
    let executableName = "pi"
    /// Pi loads every file in its user extensions folder at startup.
    let pluginFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/extensions/atoll.ts")

    // Pi's own event names, as the extension below reports them.
    let hookEvents: [String: AgentEventPhase] = [
        "session_start": .sessionStarted,
        "message_start": .promptSubmitted,
        "tool_execution_start": .toolStarted,
        "tool_execution_end": .thinking,
        "ui_prompt_start": .needsAttention,
        "ui_prompt_end": .attentionResolved,
        "agent_settled": .turnFinished,
        "session_shutdown": .sessionEnded,
    ]

    let toolKinds: [String: AgentToolKind] = [
        "ls": .read,
    ]

    var installNote: String? {
        String(localized: "Sessions that are already open pick this up after a restart.")
    }

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        if event == "agent_settled", payload["cancelled"] as? Bool == true { return .turnCancelled }
        if event == "agent_settled", (payload["error"] as? String)?.nonBlank != nil { return .turnFailed }
        return hookEvents[event]
    }

    // Only events Pi announces, never `tool_call`: Pi blocks a tool whose
    // `tool_call` handler fails, while a failing notification handler is only
    // logged. Every handler returns at once; only the report on the way out
    // waits, and briefly.
    let pluginBody = #"""
    export default function (pi) {
      let lastReply;
      let failure;
      let cancelled;
      let promptSequence = 0;
      const activePrompts = [];

      const on = (name, handler) => pi.on(name, (event, ctx) => {
        try { return handler(event, ctx); } catch {}
      });
      // Print, JSON and RPC runs (scripts, subagents) are not terminal sessions.
      const report = (event, ctx, extra) => ctx.mode !== "tui" ? undefined : atollReport(event, {
        session_id: ctx.sessionManager.getSessionId(),
        cwd: ctx.cwd,
        transcript_path: ctx.sessionManager.getSessionFile(),
        ...extra,
      });
      const text = (content) => typeof content === "string" ? content
        : Array.isArray(content) ? content.filter((block) => block?.type === "text").map((block) => block.text).join("\n\n")
        : "";

      on("session_start", (_event, ctx) => { report("session_start", ctx); });
      on("message_start", (event, ctx) => {
        if (event.message?.role === "user") report("message_start", ctx, { prompt: text(event.message.content) });
      });
      on("tool_execution_start", (event, ctx) => {
        report("tool_execution_start", ctx, { tool_name: event.toolName, tool_use_id: event.toolCallId, tool_input: event.args });
      });
      on("tool_execution_end", (event, ctx) => { report("tool_execution_end", ctx, { tool_name: event.toolName, tool_use_id: event.toolCallId }); });
      // A dialog an extension opens mid-run (an approval); one opened while idle is the user's own.
      on("ui_prompt_start", (event, ctx) => {
        if (ctx.isIdle()) return;
        // Pi has no prompt ID: correlate paired extension events locally.
        const prompt = { id: `pi-ui-${++promptSequence}`, kind: event.kind, title: event.title };
        if (activePrompts.length >= 64) { report("atoll.transport.uncertain", ctx); return; }
        activePrompts.push(prompt);
        report("ui_prompt_start", ctx, { message: event.title, request_id: prompt.id });
      });
      on("ui_prompt_end", (event, ctx) => {
        const index = activePrompts.findLastIndex((p) => p.kind === event.kind && p.title === event.title);
        if (index < 0) return;
        const [prompt] = activePrompts.splice(index, 1);
        report("ui_prompt_end", ctx, { request_id: prompt.id });
      });
      on("agent_end", (event) => {
        const last = (event.messages ?? []).filter((message) => message?.role === "assistant").pop();
        lastReply = text(last?.content) || undefined;
        cancelled = last?.stopReason === "aborted";
        failure = last?.stopReason === "error" ? (last.errorMessage || "Error") : undefined;
      });
      on("agent_settled", (_event, ctx) => {
        report("agent_settled", ctx, { last_assistant_message: lastReply, error: failure, cancelled });
        lastReply = failure = cancelled = undefined;
        activePrompts.length = 0;
      });
      // A reload keeps the session; quitting or switching sessions ends this one.
      on("session_shutdown", (event, ctx) => {
        if (event.reason === "reload") return;
        report("session_shutdown", ctx);
        return atollFlush(1500);
      });
    }

    """#

    /// Entries of Pi's session file. Pi keeps every branch in one file, so the
    /// conversation is the chain from the newest entry back through `parentId`.
    /// Thinking, tool results and Pi's own system entries are skipped.
    func transcript(from rows: [[String: Any]]) -> AgentTranscript? {
        let byID = Dictionary(rows.compactMap { row in (row["id"] as? String).map { ($0, row) } }, uniquingKeysWith: { _, newer in newer })
        var branch: [[String: Any]] = []
        var visited = Set<String>()
        var next = rows.last { $0["id"] is String }
        while let row = next, let id = row["id"] as? String, visited.insert(id).inserted {
            branch.append(row)
            next = (row["parentId"] as? String).flatMap { byID[$0] }
        }

        var messages: [AgentMessage] = []
        var title: String?
        for row in branch.reversed() {
            guard let id = row["id"] as? String else { continue }
            if row["type"] as? String == "session_info" { title = (row["name"] as? String)?.nonBlank ?? title }
            guard row["type"] as? String == "message", let message = row["message"] as? [String: Any] else { continue }
            let content = message["content"]
            let blocks = content as? [[String: Any]] ?? (content as? String).map { [["type": "text", "text": $0]] } ?? []
            switch message["role"] as? String {
            case "user":
                let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n\n")
                guard let visible = text.nonBlank else { continue }
                messages.append(AgentMessage(id: id, role: .user, text: visible))
            case "assistant":
                for (index, block) in blocks.enumerated() {
                    switch block["type"] as? String {
                    case "text":
                        if let text = (block["text"] as? String)?.nonBlank {
                            messages.append(AgentMessage(id: "\(id)-\(index)", role: .assistant, text: text))
                        }
                    case "toolCall":
                        guard let name = block["name"] as? String else { continue }
                        let detail = (block["arguments"] as? [String: Any]).flatMap(Self.toolDetail(from:)) ?? name
                        messages.append(.activity(id: block["id"] as? String ?? "\(id)-\(index)", kind: toolKind(for: name), detail: detail))
                    default: continue
                    }
                }
            default: continue
            }
        }
        return AgentTranscript(messages: Array(messages.suffix(AgentSession.messageLimit)), title: title)
    }
}
