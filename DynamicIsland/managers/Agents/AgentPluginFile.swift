import Foundation

/// An agent that loads plugins instead of running hook commands (Pi, OpenCode).
/// Atoll installs one plugin file of its own, which hands each event to the
/// same hook script hook commands run, so everything after the plugin is
/// shared with `HookConfigAgentSource`s and its events use `hookEvents` names.
///
/// A plugin runs inside the agent, so it only ever observes: it subscribes to
/// events that notify, never to ones that can change or block a tool call, and
/// the agent never waits on it while it works.
protocol PluginAgentSource: AgentSource {
    /// A path the agent loads user plugins from. Atoll owns this one file.
    var pluginFileURL: URL { get }
    /// The plugin's own part: what it subscribes to, and what it reports with
    /// `atollReport(event, payload)` from `AgentPluginFile.preamble`. Payloads
    /// use Claude Code's keys (`session_id`, `tool_name`, ...).
    var pluginBody: String { get }
}

extension PluginAgentSource {
    var installation: AgentHookInstallation {
        AgentPluginFile(fileURL: pluginFileURL, sourceID: id, body: pluginBody)
    }
}

/// A plugin file Atoll writes whole and removes whole.
struct AgentPluginFile: AgentHookInstallation {
    let fileURL: URL
    let sourceID: String
    let body: String

    func contents(scriptPath: String) -> String {
        Self.preamble(scriptPath: scriptPath, sourceID: sourceID) + body
    }

    private var current: String? { try? String(contentsOf: fileURL, encoding: .utf8) }

    func isInstalled(scriptPath: String) -> Bool {
        current == contents(scriptPath: scriptPath)
    }

    func isOutdated(scriptPath: String) -> Bool {
        guard let current else { return false }
        return current.contains(AgentHooksFile.marker) && current != contents(scriptPath: scriptPath)
    }

    func install(scriptPath: String) throws {
        // A file of that name that Atoll did not write is the user's own.
        if let current, !current.contains(AgentHooksFile.marker) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents(scriptPath: scriptPath).utf8).write(to: fileURL, options: .atomic)
    }

    func remove() throws {
        guard let current, current.contains(AgentHooksFile.marker) else { return }
        let fileManager = FileManager.default
        try fileManager.removeItem(at: fileURL)
        // The plugin folder goes too when Atoll's file was all it held.
        let folder = fileURL.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fileManager.removeItem(at: folder)
        }
    }

    /// What every Atoll plugin starts with: `atollReport`, which runs the hook
    /// script once per event, and `atollFlush`, for a report sent on the way out.
    static func preamble(scriptPath: String, sourceID: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        func literal(_ text: String) -> String {
            String(decoding: (try? encoder.encode(text)) ?? Data(#""""#.utf8), as: UTF8.self)
        }
        return #"""
        // Installed by Atoll, which rewrites or removes this file as a whole.
        // Reports this agent's sessions to Atoll's notch through Atoll's hook
        // script. It only observes: nothing here changes, blocks or holds up the agent.
        import { spawn } from "node:child_process";

        const ATOLL_HOOK = \#(literal(scriptPath));
        const ATOLL_SOURCE = \#(literal(sourceID));
        let atollQueue = Promise.resolve();
        let atollDraining = false;
        const atollEvents = [];
        const atollUncertain = new Map();
        const atollCritical = /(?:permission|question|ui_prompt|settled|Stop|error|cancelled|idle|deleted|shutdown|dispose|session_start|session.created|chat.message|message_start)/;

        function atollMarkUncertain(payload) {
          const session = payload.session_id;
          if (!session) return;
          atollUncertain.set(session, { session_id: session, cwd: payload.cwd });
          // Match the application's bounded session store; overflow cannot grow memory.
          if (atollUncertain.size > 64) atollUncertain.delete(atollUncertain.keys().next().value);
        }

        function atollBoundPayload(payload) {
          const bounded = {};
          for (const [key, value] of Object.entries(payload).slice(0, 32)) {
            if (key.length > 128) continue;
            if (typeof value === "string") {
              const limit = key === "prompt" || key === "last_assistant_message" ? 16384 : (key === "cwd" || key === "session_id" || key === "transcript_path" ? 4096 : 256);
              bounded[key] = value.slice(0, limit);
            } else if (typeof value === "number" || typeof value === "boolean" || value == null) {
              bounded[key] = value;
            }
          }
          if (payload.tool_input && typeof payload.tool_input === "object") {
            bounded.tool_input = {};
            for (const [key, value] of Object.entries(payload.tool_input).slice(0, 16)) {
              if (key.length > 128) continue;
              if (typeof value === "string") bounded.tool_input[key] = value.slice(0, 1024);
              else if (Array.isArray(value)) bounded.tool_input[key] = value.slice(0, 8).filter(x => typeof x === "string").map(x => x.slice(0, 128));
            }
          }
          // Detached JSON copy avoids retaining a giant provider string through
          // a sliced string or a mutable tool-input object in the queue.
          return JSON.parse(JSON.stringify(bounded));
        }

        function atollSend(event, payload) {
          return new Promise((resolve) => {
            let child;
            let completed = false;
            let timedOut = false;
            const done = (failed = false) => {
              if (completed) return;
              completed = true;
              clearTimeout(timer);
              if (failed && event !== "atoll.transport.uncertain") atollMarkUncertain(payload);
              resolve();
            };
            const timer = setTimeout(() => {
              timedOut = true;
              try { if (!child?.kill("SIGKILL")) done(true); } catch { done(true); }
            }, 2000);
            try {
              child = spawn("/bin/sh", [ATOLL_HOOK, ATOLL_SOURCE, event], { stdio: ["pipe", "ignore", "ignore"] });
              child.on("error", () => done(true));
              child.on("close", (code, signal) => done(timedOut || signal != null || (code !== 0 && code != null)));
              child.stdin.on("error", () => {
                // A broken pipe does not prove the child exited. Terminate it
                // and wait for close before starting the next owned child.
                timedOut = true;
                try { if (!child.kill("SIGKILL")) done(true); } catch { done(true); }
              });
              child.stdin.end(JSON.stringify(payload));
            } catch { done(true); }
          });
        }

        // One owned child at a time. Ordinary activity is coalesced at capacity;
        // critical requests/final states have a reserved lane. If even that fills,
        // explicitly invalidate the affected session instead of silently lying.
        function atollReport(event, payload) {
          try { payload = atollBoundPayload(payload); } catch { return atollQueue; }
          const critical = atollCritical.test(event);
          if (!critical && atollEvents.length >= 32) {
            const previous = atollEvents.findIndex((x) => !x.critical && x.payload.session_id === payload.session_id && x.event === event);
            if (previous >= 0) atollEvents[previous] = { event, payload, critical };
            else atollMarkUncertain(payload);
          } else {
            if (atollEvents.length >= 64) {
              const ordinary = atollEvents.findIndex((x) => !x.critical);
              const [lost] = atollEvents.splice(ordinary >= 0 ? ordinary : 0, 1);
              atollMarkUncertain(lost.payload);
            }
            atollEvents.push({ event, payload, critical });
          }
          return atollDrain();
        }

        function atollDrain() {
          if (atollDraining) return atollQueue;
          atollDraining = true;
          atollQueue = Promise.resolve().then(async () => {
            while (atollEvents.length || atollUncertain.size) {
              if (!atollEvents.length && atollUncertain.size) {
                const [session, uncertain] = atollUncertain.entries().next().value;
                atollUncertain.delete(session);
                await atollSend("atoll.transport.uncertain", uncertain);
              } else {
                const next = atollEvents.shift();
                await atollSend(next.event, next.payload);
              }
            }
          }).finally(() => {
            atollDraining = false;
            // A report can arrive in a microtask after the loop empties but
            // before finally runs. Adopt its drain so flush still waits for it.
            if (atollEvents.length || atollUncertain.size) return atollDrain();
          });
          return atollQueue;
        }

        // Waits at most `ms` for the reports so far, for an agent about to exit.
        function atollFlush(ms) {
          let timer;
          const timeout = new Promise((resolve) => { timer = setTimeout(resolve, ms); });
          return Promise.race([atollQueue, timeout]).finally(() => clearTimeout(timer));
        }


        """#
    }
}
