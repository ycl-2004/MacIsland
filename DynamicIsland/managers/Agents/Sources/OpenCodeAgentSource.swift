import Foundation
import SwiftUI

struct OpenCodeAgentSource: PluginAgentSource {
    let id = "opencode"
    let displayName = "OpenCode"
    let symbolName = "curlybraces"
    let accentColor = Color(red: 0.95, green: 0.78, blue: 0.36)
    let executableName = "opencode"
    /// OpenCode loads every file in its global plugins folder at startup.
    let pluginFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/plugins/atoll.js")

    // OpenCode's own event names, as the plugin below reports them. OpenCode
    // keeps conversations in a database rather than a transcript file, so the
    // plugin also carries the prompt and the final reply.
    let hookEvents: [String: AgentEventPhase] = [
        "session.created": .sessionStarted,
        "chat.message": .promptSubmitted,
        "tool.running": .toolStarted,
        "tool.completed": .thinking,
        "permission.asked": .needsAttention,
        "question.asked": .needsAttention,
        "permission.replied": .attentionResolved,
        "question.replied": .attentionResolved,
        "question.rejected": .attentionResolved,
        "session.idle": .turnFinished,
        "session.error": .turnFailed,
        "session.cancelled": .turnCancelled,
        "session.deleted": .sessionEnded,
        "dispose": .sessionEnded,
    ]

    let toolKinds: [String: AgentToolKind] = [
        "todowrite": .other,
        "todoread": .other,
        "question": .other,
        "skill": .other,
    ]

    var installNote: String? {
        String(localized: "Sessions that are already open pick this up after a restart.")
    }

    // Only the `event` stream, which observes. Hooks that can rewrite a tool
    // call or answer a permission (`tool.execute.before`, `permission.ask`) are
    // never registered. Streaming text stays in memory; only a change of state
    // runs the hook script.
    let pluginBody = #"""
    const remembered = (limit) => {
      const map = new Map();
      return {
        get: (key) => map.get(key),
        has: (key) => map.has(key),
        delete: (key) => map.delete(key),
        keys: () => [...map.keys()],
        set(key, value) {
          map.delete(key);
          map.set(key, value);
          if (map.size > limit) map.delete(map.keys().next().value);
        },
      };
    };

    export const AtollPlugin = async ({ directory }) => {
      const roles = remembered(512);     // message id → "user" | "assistant"
      const children = remembered(256);  // sessions a subagent runs, part of their parent's card
      const prompts = remembered(256);   // user messages already reported
      const tools = remembered(256);     // tool call id → status last reported
      const replies = remembered(64);    // session id → latest assistant text
      const reported = remembered(64);   // sessions shown, ended when OpenCode exits

      const report = (event, sessionID, extra) => {
        reported.set(sessionID, true);
        return atollReport(event, { session_id: sessionID, cwd: directory, ...extra });
      };

      return {
        event: async ({ event }) => {
          try {
            const type = event?.type ?? "";
            const props = event?.properties ?? {};
            const info = props.info;
            if (type.startsWith("session.") && info?.parentID) children.set(info.id, true);
            const sessionID = props.sessionID ?? props.part?.sessionID ?? info?.sessionID ?? info?.id;
            if (typeof sessionID !== "string" || children.has(sessionID)) return;

            switch (type) {
              case "session.created":
                report(type, sessionID);
                break;
              case "message.updated":
                roles.set(info.id, info.role);
                break;
              case "message.part.updated": {
                const part = props.part;
                if (part?.type === "text" && !part.synthetic && typeof part.text === "string") {
                  if (roles.get(part.messageID) === "assistant") {
                    replies.set(sessionID, part.text);
                  } else if (roles.get(part.messageID) === "user" && !prompts.has(part.messageID)) {
                    prompts.set(part.messageID, true);
                    report("chat.message", sessionID, { prompt: part.text });
                  }
                } else if (part?.type === "tool") {
                  const status = part.state?.status;
                  if (status === tools.get(part.callID)) break;
                  tools.set(part.callID, status);
                  if (status === "running") {
                    report("tool.running", sessionID, { tool_name: part.tool, tool_use_id: part.callID, tool_input: part.state.input });
                  } else if (status === "completed" || status === "error") {
                    report("tool.completed", sessionID, { tool_name: part.tool, tool_use_id: part.callID });
                  }
                }
                break;
              }
              case "permission.asked":
                report(type, sessionID, { tool_name: props.permission, request_id: props.id });
                break;
              case "question.asked":
                report(type, sessionID, { message: props.questions?.[0]?.question, request_id: props.id });
                break;
              case "permission.replied":
              case "question.replied":
              case "question.rejected":
                report(type, sessionID, { request_id: props.requestID });
                break;
              case "session.idle":
                report(type, sessionID, { last_assistant_message: replies.get(sessionID) });
                replies.delete(sessionID);
                break;
              case "session.error":
                // Stopping a turn with Esc is not a failure; `session.idle` follows.
                if (props.error?.name === "MessageAbortedError") {
                  report("session.cancelled", sessionID);
                } else {
                  report(type, sessionID, { error: props.error?.data?.message ?? props.error?.name ?? "Error" });
                }
                break;
              case "session.deleted":
                report(type, sessionID);
                reported.delete(sessionID);
                break;
            }
          } catch {}
        },
        dispose: async () => {
          try {
            for (const sessionID of reported.keys()) report("dispose", sessionID);
            await atollFlush(1500);
          } catch {}
        },
      };
    };

    """#
}
