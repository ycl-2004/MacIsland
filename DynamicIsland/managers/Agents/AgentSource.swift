import Foundation
import SwiftUI

/// How a message typed in Atoll reaches a terminal session of one agent.
enum AgentReplyDelivery {
    /// Codex's shared service takes the message directly, idle or busy.
    case sharedService
    /// A hook parks while the agent waits for the user and wakes it with the
    /// message (Claude Code's `asyncRewake`), so only while it is idle. The
    /// handler is installed on `hookEvent` with these extra `options`.
    case wakeWhenIdle(hookEvent: String, options: [String: Any])
    /// The agent's per-step hook picks the message up and hands it over as a
    /// user step, so only while the agent works (Antigravity has no async hooks).
    case injectWhileWorking
}

/// The recent conversation read back from an agent's own transcript file.
struct AgentTranscript {
    let messages: [AgentMessage]
    /// The title the agent gave the session, when it has one.
    var title: String? = nil
}

/// One coding agent Atoll can follow through its hooks (Claude Code, Codex, ...).
///
/// A source only *declares* what is specific to its agent: how Atoll's hooks
/// get into it (`HookConfigAgentSource` or `PluginAgentSource`), which hook
/// events it has and what they mean, what its tools are called, how its
/// transcript reads and how a typed message reaches it. Everything mechanical —
/// turning a hook payload into an `AgentHookEvent`, adding or removing Atoll's
/// hooks, reading transcripts and carrying messages — is shared, so a new agent
/// is one small type plus one line in `AgentSourceRegistry`.
protocol AgentSource {
    /// Stable identifier, used in hook commands and to route incoming events.
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var accentColor: Color { get }
    /// Name of the CLI, used to tell the user whether the agent is installed.
    var executableName: String { get }
    /// Where Atoll's hooks go and how they are added and removed.
    var installation: AgentHookInstallation { get }
    /// Set on every hook this agent runs. Another source's hook that runs with
    /// it set came from this agent reading that source's config (Grok Build runs
    /// Claude Code's hooks), so it is dropped instead of showing a second card.
    var hookEnvironmentVariable: String? { get }
    /// Hook event names this agent emits (or Atoll's plugin reports for it),
    /// mapped to the lifecycle step they mean. Only these are installed, so an
    /// event the agent does not know about is never written into its config.
    var hookEvents: [String: AgentEventPhase] { get }
    /// Tool names this agent uses, where the name alone does not reveal the kind.
    var toolKinds: [String: AgentToolKind] { get }
    /// Shown under the install button when the agent needs an extra step.
    var installNote: String? { get }
    /// How a message typed in Atoll reaches this agent, or nil when it cannot.
    var replyDelivery: AgentReplyDelivery? { get }
    /// The lifecycle step one event means. Override when the event name alone
    /// is not enough to tell (the default just looks it up in `hookEvents`).
    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase?
    /// The conversation in rows of the agent's JSONL transcript, or nil when
    /// Atoll reads this agent's history some other way.
    func transcript(from rows: [[String: Any]]) -> AgentTranscript?
    /// What a hook prints to hand `message` to the agent at `event`, for
    /// `.injectWhileWorking`; nil when that event cannot carry it.
    func replyOutput(_ message: String, atEvent event: String) -> Data?
}

extension AgentSource {
    var hookEnvironmentVariable: String? { nil }
    var installNote: String? { nil }
    var replyDelivery: AgentReplyDelivery? { nil }
    func transcript(from rows: [[String: Any]]) -> AgentTranscript? { nil }
    func replyOutput(_ message: String, atEvent event: String) -> Data? { nil }

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        hookEvents[event]
    }

    // MARK: Payload normalisation

    // Claude Code and Codex send snake_case keys; Antigravity sends camelCase
    // protojson; Grok Build sends both for some fields and camelCase for the
    // rest. Atoll's own plugins send Claude's keys. Reading every spelling here
    // keeps each source free of payload parsing.

    func makeEvent(eventName: String, payload: [String: Any], hostBundleID: String?, now: Date = Date()) -> AgentHookEvent? {
        guard let phase = eventName == "atoll.transport.uncertain" ? AgentEventPhase.statusUncertain : phase(forEvent: eventName, payload: payload) else { return nil }
        let cwd = payload["cwd"] as? String ?? (payload["workspacePaths"] as? [String])?.first
        let sessionKey = ["session_id", "conversationId", "sessionId", "thread_id"]
            .lazy.compactMap { payload[$0] as? String }.first { !$0.isEmpty }
            ?? "cwd:\(cwd ?? "unknown")"
        let toolCall = payload["toolCall"] as? [String: Any]
        let toolName = payload["tool_name"] as? String ?? toolCall?["name"] as? String
        let toolInput = payload["tool_input"] as? [String: Any] ?? toolCall?["args"] as? [String: Any]

        var message = payload["message"] as? String ?? (payload["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if phase == .needsAttention, message == nil, let toolName {
            message = String(localized: "Wants to use \(toolName)")
        }

        return AgentHookEvent(
            sourceID: id,
            phase: phase,
            sessionKey: sessionKey,
            cwd: cwd,
            prompt: payload["prompt"] as? String,
            toolName: toolName,
            toolKind: toolName.map(toolKind(for:)),
            toolDetail: toolInput.flatMap(Self.toolDetail(from:)),
            message: message,
            lastReply: (payload["last_assistant_message"] ?? payload["lastAssistantMessage"]) as? String,
            hostBundleID: hostBundleID,
            transcriptPath: ((payload["transcript_path"] ?? payload["transcriptPath"]) as? String)?.nonBlank,
            eventName: eventName,
            turnID: ((payload["turn_id"] ?? payload["turnId"]) as? String)?.nonBlank,
            toolUseID: ((payload["tool_use_id"] ?? payload["toolCallId"] ?? toolCall?["id"]) as? String)?.nonBlank,
            requestID: ((payload["request_id"] ?? payload["requestID"]) as? String)?.nonBlank,
            receivedAt: now
        )
    }

    func toolKind(for toolName: String) -> AgentToolKind {
        if let declared = toolKinds[toolName] { return declared }
        // MCP and plugin tools follow no convention, so fall back to the verb in the name.
        let name = toolName.lowercased()
        let hints: [(AgentToolKind, [String])] = [
            (.command, ["bash", "shell", "exec", "command", "terminal"]),
            (.edit, ["edit", "write", "patch", "replace", "create_file"]),
            (.web, ["web", "fetch", "url", "browser"]),
            (.search, ["grep", "glob", "search", "find"]),
            (.read, ["read", "view", "list", "open"]),
            (.delegate, ["agent", "task", "subagent"]),
        ]
        return hints.first { _, words in words.contains(where: name.contains) }?.0 ?? .other
    }

    /// The one input field that best says what a tool call is doing. Keys are
    /// matched case-insensitively (`command` vs Antigravity's `CommandLine`).
    static func toolDetail(from input: [String: Any]) -> String? {
        let byLowercasedKey = Dictionary(input.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let fileKeys: Set = ["file_path", "filepath", "targetfile", "target_file", "absolutepath", "path", "target_directory"]
        let keys = ["command", "commandline", "cmd", "file_path", "filepath", "targetfile", "target_file", "absolutepath", "path",
                    "target_directory", "pattern", "query", "url", "description"]
        for key in keys {
            let value: String?
            switch byLowercasedKey[key] {
            case let string as String: value = string
            case let parts as [String]: value = parts.joined(separator: " ")
            default: value = nil
            }
            guard var value, !value.isEmpty else { continue }
            if fileKeys.contains(key) {
                value = URL(fileURLWithPath: value).lastPathComponent
            }
            let singleLine = value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
            return singleLine.count > 80 ? String(singleLine.prefix(79)) + "…" : singleLine
        }
        return nil
    }

    var isCLIAvailable: Bool {
        AgentExecutableLocator.path(for: executableName) != nil
    }
}

// MARK: - Installation

/// Where Atoll's hooks live in one agent, and how they are added and removed.
/// Every kind tells Atoll's hooks apart by `AgentHooksFile.marker`.
protocol AgentHookInstallation {
    /// The file Atoll writes, named when writing it fails.
    var fileURL: URL { get }
    func isInstalled(scriptPath: String) -> Bool
    /// Some of Atoll's hooks are there, but not the current set.
    func isOutdated(scriptPath: String) -> Bool
    func install(scriptPath: String) throws
    func remove() throws
}

/// An agent that runs the commands listed in a JSON hooks config (Claude Code,
/// Codex, Antigravity, Grok Build). Atoll adds its own entries beside the user's.
protocol HookConfigAgentSource: AgentSource {
    /// The user-level JSON file the agent reads hooks from.
    var hooksFileURL: URL { get }
    /// How hooks are laid out in `hooksFileURL`.
    var hookFormat: AgentHookConfigFormat { get }
    /// What the hook prints back, for agents that require a reply on stdout.
    var hookReply: String? { get }
}

extension HookConfigAgentSource {
    var hookFormat: AgentHookConfigFormat { GroupedHookFormat() }
    var hookReply: String? { nil }

    var installation: AgentHookInstallation {
        HookConfigInstallation(fileURL: hooksFileURL, format: hookFormat, handlers: hookHandlers(scriptPath:))
    }

    func hookCommand(event: String, scriptPath: String) -> String {
        var command = "/bin/sh '\(scriptPath)' \(id) \(event)"
        if let hookReply { command += " '\(hookReply)'" }
        return command
    }

    /// Every handler Atoll installs, by event: one per lifecycle event, plus the
    /// parked reply hook for agents woken from Atoll.
    func hookHandlers(scriptPath: String) -> [String: [[String: Any]]] {
        var handlers = Dictionary(uniqueKeysWithValues: hookEvents.keys.map {
            ($0, [["type": "command", "command": hookCommand(event: $0, scriptPath: scriptPath), "timeout": 5] as [String: Any]])
        })
        if case .wakeWhenIdle(let event, let options) = replyDelivery {
            let wait: [String: Any] = ["type": "command", "command": "/bin/sh '\(scriptPath)' \(id) wait"]
            handlers[event, default: []].append(wait.merging(options) { current, _ in current })
        }
        return handlers
    }
}

/// Atoll's entries in an agent's JSON hooks config.
struct HookConfigInstallation: AgentHookInstallation {
    let fileURL: URL
    let format: AgentHookConfigFormat
    let handlers: (_ scriptPath: String) -> [String: [[String: Any]]]

    func isInstalled(scriptPath: String) -> Bool {
        guard let root = try? AgentHooksFile(url: fileURL).read() else { return false }
        return format.containsAll(handlers(scriptPath), in: root)
    }

    func isOutdated(scriptPath: String) -> Bool {
        guard let root = try? AgentHooksFile(url: fileURL).read() else { return false }
        return format.containsAtoll(in: root) && !format.containsAll(handlers(scriptPath), in: root)
    }

    func install(scriptPath: String) throws {
        try AgentHooksFile(url: fileURL).update { root in
            format.install(handlers(scriptPath), into: &root)
        }
    }

    func remove() throws {
        try AgentHooksFile(url: fileURL).update { root in
            format.remove(from: &root)
        }
    }
}

// MARK: - Hook config formats

/// How one agent lays out hooks in its JSON config. Every format tells Atoll's
/// handlers apart by the script path in their command.
protocol AgentHookConfigFormat {
    func containsAll(_ handlers: [String: [[String: Any]]], in root: [String: Any]) -> Bool
    func containsAtoll(in root: [String: Any]) -> Bool
    func install(_ handlers: [String: [[String: Any]]], into root: inout [String: Any])
    func remove(from root: inout [String: Any])
}

extension AgentHookConfigFormat {
    static func isAtoll(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(AgentHooksFile.marker) ?? false
    }

    /// Atoll's handlers for one event already read exactly as `wanted`.
    static func matches(_ present: [[String: Any]], _ wanted: [[String: Any]]) -> Bool {
        NSArray(array: present.filter(isAtoll)).isEqual(to: wanted)
    }
}

/// `{"hooks": {"Event": [{"hooks": [handler, ...]}, ...]}}` — Claude Code and Codex.
/// Atoll's handlers sit in their own group, after the user's.
struct GroupedHookFormat: AgentHookConfigFormat {
    func containsAll(_ handlers: [String: [[String: Any]]], in root: [String: Any]) -> Bool {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        return handlers.allSatisfy { event, wanted in Self.matches(Self.handlers(in: hooks[event]), wanted) }
    }

    func containsAtoll(in root: [String: Any]) -> Bool {
        (root["hooks"] as? [String: Any] ?? [:]).values.contains { Self.handlers(in: $0).contains(where: Self.isAtoll) }
    }

    func install(_ handlers: [String: [[String: Any]]], into root: inout [String: Any]) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        // Events Atoll no longer uses lose its handlers; the rest are only
        // touched when their handlers changed. Codex keys its per-hook trust by
        // position, so a new group is appended — never inserted before others.
        for event in hooks.keys where handlers[event] == nil {
            hooks[event] = Self.withoutAtoll(hooks[event])
        }
        for (event, wanted) in handlers.sorted(by: { $0.key < $1.key }) {
            guard !Self.matches(Self.handlers(in: hooks[event]), wanted) else { continue }
            var groups = Self.withoutAtoll(hooks[event]) as? [[String: Any]] ?? []
            groups.append(["hooks": wanted])
            hooks[event] = groups
        }
        root["hooks"] = hooks
    }

    func remove(from root: inout [String: Any]) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in hooks.keys { hooks[event] = Self.withoutAtoll(hooks[event]) }
        root["hooks"] = hooks.isEmpty ? nil : hooks
    }

    private static func handlers(in groups: Any?) -> [[String: Any]] {
        (groups as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    /// The event's groups with Atoll's handlers dropped, and groups left empty removed.
    private static func withoutAtoll(_ groups: Any?) -> Any? {
        guard let groups = groups as? [[String: Any]] else { return groups }
        let remaining = groups.compactMap { group -> [String: Any]? in
            let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter { !isAtoll($0) }
            guard !handlers.isEmpty else { return nil }
            var group = group
            group["hooks"] = handlers
            return group
        }
        return remaining.isEmpty ? nil : remaining
    }
}

/// `{"<hook name>": {"Event": ...}}` — Antigravity. Atoll owns one named hook
/// outright. Tool events wrap handlers in `matcher` groups; the others list
/// handlers directly.
struct NamedHookFormat: AgentHookConfigFormat {
    let name: String
    let toolEvents: Set<String>

    func containsAll(_ handlers: [String: [[String: Any]]], in root: [String: Any]) -> Bool {
        guard let spec = root[name] as? [String: Any] else { return false }
        return handlers.allSatisfy { event, wanted in
            let entries = spec[event] as? [[String: Any]] ?? []
            let present = toolEvents.contains(event) ? entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] } : entries
            return Self.matches(present, wanted)
        }
    }

    func containsAtoll(in root: [String: Any]) -> Bool { root[name] != nil }

    func install(_ handlers: [String: [[String: Any]]], into root: inout [String: Any]) {
        var spec: [String: Any] = [:]
        for (event, wanted) in handlers {
            spec[event] = toolEvents.contains(event) ? [["matcher": "*", "hooks": wanted]] : wanted
        }
        root[name] = spec
    }

    func remove(from root: inout [String: Any]) {
        root[name] = nil
    }
}

// MARK: - Files

/// Reads and rewrites one agent's JSON config, keeping a copy of the file as it
/// was before Atoll first changed it.
struct AgentHooksFile {
    /// Every command Atoll installs runs this script, which is how its handlers
    /// are told apart from the user's own.
    static let marker = "AgentBridge/agent-hook.sh"

    let url: URL

    func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        // A file that is not a JSON object is left alone rather than overwritten.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return root
    }

    func update(_ mutate: (inout [String: Any]) -> Void) throws {
        var root = try read()
        mutate(&root)
        let fm = FileManager.default
        let backup = url.appendingPathExtension("atoll-backup")
        // Only a file Atoll has never written to is the user's original.
        if let original = try? String(contentsOf: url, encoding: .utf8),
           !original.contains(Self.marker), !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: url, to: backup)
        }
        // A file Atoll created itself goes away again once it holds nothing.
        if root.isEmpty, !fm.fileExists(atPath: backup.path) {
            try? fm.removeItem(at: url)
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

enum AgentExecutableLocator {
    /// GUI apps do not inherit the shell's `PATH`, so look where installers put
    /// CLIs, including the agents' own installers (OpenCode, Grok Build).
    private static let searchDirectories = [
        "~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "~/.npm-global/bin", "~/.bun/bin",
        "~/.opencode/bin", "~/.grok/bin", "/usr/bin",
    ].map { NSString(string: $0).expandingTildeInPath }

    static func path(for executable: String) -> String? {
        searchDirectories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(executable).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
