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
        let atollPending = 0;

        // Hands one event to the hook script, one at a time so that events arrive
        // in order. Never throws, and nothing the agent does waits for it.
        function atollReport(event, payload) {
          if (atollPending >= 32) return atollQueue;
          atollPending += 1;
          atollQueue = atollQueue.then(() => new Promise((resolve) => {
            const done = () => { clearTimeout(timer); resolve(); };
            const timer = setTimeout(done, 2000);
            try {
              const child = spawn("/bin/sh", [ATOLL_HOOK, ATOLL_SOURCE, event], { stdio: ["pipe", "ignore", "ignore"] });
              child.on("error", done);
              child.on("close", done);
              child.stdin.on("error", () => {});
              child.stdin.end(JSON.stringify(payload));
            } catch {
              done();
            }
          })).finally(() => { atollPending -= 1; });
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
