# Architecture: window sizing pipeline & agent bridge

Updated 2026-10-06. These are the two subsystems most likely to break in
non-obvious ways when edited. Everything here describes the code as it is,
not as it should be.

## Product scope

Atoll is a lightweight notch utility for temporary content, work status and a
small set of quick actions. Prioritize interaction, feature management and
bounded background work when improving the existing app.

The user has excluded unlimited clipboard history, a full AI workspace, a
plugin marketplace and additional complex audio features from the development
scope. Terminal remains a possible later addition; it is not part of the
current work. These decisions do not remove existing optional capabilities.
See the [product research](notch-product-research-2026-10-06.md) for the
supporting comparison and proposed improvements.

## Window sizing pipeline

Atoll renders every notch surface (closed HUD, open tabs, lock screen panels)
inside borderless `DynamicIslandWindow` NSPanels pinned at `+.mainMenu + 3`.
The AppKit window frame and the SwiftUI content size are computed separately
and must agree; the window is the larger of the two.

### The invariant

**The window is never smaller than the open notch, even while the notch is
closed.** A closed-notch HUD that needs more room than the open notch still
gets it. If the window grew and shrank with the notch's open/close animation,
SwiftUI would animate the content from the notch's position inside the old
frame: the notch would jump sideways and grow from a corner. Keeping the frame
fixed lets the open/close animation run purely inside SwiftUI.

### Who computes what

| Step | Owner | Input | Output |
| --- | --- | --- | --- |
| Closed-HUD demand | `AppDelegate.closedHUDWindowSize()` | connectivity HUD, inline sneak peek, recording HUD, battery HUD state | `CGSize?` — `nil` when no closed HUD is showing |
| Open-tab demand | `AppDelegate.standardWindowSize()` | `coordinator.currentView`, stats/inline-lyrics adjustments | open notch size + shadow padding |
| Window target | `AppDelegate.calculateRequiredNotchSize()` | `max(closedHUDWindowSize(), standardWindowSize())` per axis | the size every window is resized to |
| Per-screen adjustment | `AppDelegate.adjustedSizeForScreen(_:screen:)` | physical-notch vs island (non-notch) screen | adds top bleed (notch screens) or shadow inset ×2 (island mode) |
| Frame application | `AppDelegate.resizeWindow(_:on:to:animated:)` | target size + screen frame | clamped (never wider than the screen), centered, top-anchored `setFrame` |
| SwiftUI content size | `ContentView.dynamicNotchSize` / `DynamicIslandViewModel.calculateDynamicNotchSize()` | same tab/HUD state | the size the SwiftUI layout actually draws at |

`AppDelegate` owns the AppKit frames for all windows (one per screen when
"show on all displays" is on). `ContentView` computes the same HUD math again
for layout. These are two views of one truth, so every HUD size lives in one
tested pure helper that both sides call: `RecordingHUDLayout`,
`NetworkConnectivityHUDMetrics`, `TimerHUDMetrics`, `FlyoutFrameCalculator`,
`InlineSneakPeekMetrics`, and `BatteryTemporaryHUDKind.metrics(...)` (which the
battery HUD itself also draws at). A new closed HUD gets its own helper rather
than numbers written into `closedHUDWindowSize()` and `dynamicNotchSize`.

### Resize triggers

- Tab switch: `coordinator.$currentView` → `updateWindowSizeForTabSwitch()`
  (immediate, forced, so the notch stays pinned while animating).
- Settings that change the open size (stats graphs, `openNotchWidth`, …):
  `debouncedUpdateWindowSize()` (0.15 s).
- Connectivity HUD state: `networkConnectivityManager.$hudState`, deferred one
  main-run-loop turn because `@Published` fires on `willSet`.
- Space/screen changes: `reassertDynamicIslandWindowSpacePresence()` re-pins
  `collectionBehavior` and re-syncs `NotchSpaceManager` membership; screen
  parameter changes rebuild windows via `screenConfigurationDidChange`.
- Lock/unlock: windows are ordered out with `alphaValue = 0` and restored one
  second after unlock (no resize involved).

### Sizing gotchas

- `vm.notchSize` is the *content* size SwiftUI animates; the *window* frame
  follows `calculateRequiredNotchSize()`. Updating one without the other
  desynchronizes hover targets from what is drawn.
- `@Published` emits before the new value is assigned, so every observer that
  reads the value inside its handler must hop to the next run-loop turn
  (`DispatchQueue.main.async`) — several call sites document this; keep the
  hop when refactoring.
- The notch's `FirstMouseHostingView` sits inside a plain `NSView` content
  container, with `sizingOptions = []` and width/height autoresizing. AppDelegate
  owns the window frame; the container and hosting view follow it. Do not assign
  the hosting view directly as `window.contentView`: on macOS 27.0.1, four crash
  reports show SwiftUI's `windowDidLayout → updateAnimatedWindowSize` repeatedly
  resizing `DynamicIslandWindow`, despite the existing empty sizing options.
  AppKit aborts once layout/constraint updates exceed its display-cycle limit.
  See [music gesture crash investigation](music-gesture-crash.md).
- Shadow padding is added *before* window sizing and trimmed by
  `notchHorizontalPadding` inside `ContentView`, so hit areas cover the drawn
  notch, not the shadow.
- All main-notch activities share their outer surface's positioning; do not
  offset only the inner contents to avoid application menus. That moved recording,
  music and other activities outside a fixed clip when switching to Chrome.
  `ContentView` no longer subscribes to menu geometry or applies menu clearance;
  hover rectangles use the whole-surface `notchCenterShift` too. There is no
  timer-only opt-out preference. See the [all-path audit](music-timer-shift.md#all-path-follow-up--2026-10-05).

## Agent bridge data flow

Local-only pipeline that surfaces Claude Code / Codex / Antigravity / Pi /
OpenCode / Grok Build sessions in the notch. No network leaves the machine.

```text
agent process (hook configured once, or Atoll's plugin file for Pi / OpenCode)
  └─ agent-hook.sh (installed under ~/Library/Application Support/Atoll/AgentBridge)
       └─ curl → 127.0.0.1:<port>/v1/agent/event | /v1/agent/wait
            └─ AgentEventServer (NWListener, loopback-only, bearer token)
                 └─ AgentBridge.route → AgentHookReceiver (AgentConversationService)
                      ├─ AgentSessionStore.apply(event)  → @Published sessions → notch cards
                      └─ parked /wait hooks  ← messages typed in the notch conversation view
```

### Installation and credentials

- `AgentBridge.start()` writes `agent-hook.sh`, `auth-header`
  (`Authorization: Bearer <token>`), and later `port` into a `0o700` private
  directory. The hook script re-reads the port and header on every call, so
  hooks installed once survive relaunches; with no `port` file the script
  exits immediately and never blocks the agent.
- Each `AgentSource` (Sources/*AgentSource.swift) declares its events and
  transcript format; payload decoding (`makeEvent`) is shared. How hooks get
  in is `source.installation`, one of two kinds:
  - `HookConfigAgentSource` (Claude Code, Codex, Antigravity, Grok Build):
    Atoll's entries in the agent's JSON hooks config, beside the user's.
    Grok's live in their own file, `~/.grok/hooks/atoll.json`.
  - `PluginAgentSource` (Pi, OpenCode): agents without hook commands get one
    plugin file Atoll owns (`~/.pi/agent/extensions/atoll.ts`,
    `~/.config/opencode/plugins/atoll.js`), built from
    `AgentPluginFile.preamble` plus the source's `pluginBody`. The plugin runs
    `agent-hook.sh` per event, serialized, never awaited by the agent.
- Atoll's hooks only observe. They print nothing for any agent except the
  deliberate replies (Antigravity's required `{}`, injected messages), and
  plugins subscribe only to notification events: never Pi's `tool_call`
  (a failing handler there blocks the tool) or OpenCode's
  `tool.execute.before` / `permission.ask`.
- Events carry the hosting app (`__CFBundleIdentifier`), the terminal pane
  (per-terminal environment variables, sanitized to `[A-Za-z0-9._:-]`, ≤128
  chars), and the hook's parent PID.
- An agent that also runs another agent's hooks declares
  `hookEnvironmentVariable`: Grok Build runs `~/.claude/settings.json` hooks
  with `GROK_HOOK_EVENT` set, so the script drops every non-`grok` event in
  that environment. Without this a Grok session showed up as a Claude Code
  card, and Claude's `wait` hook (whose `asyncRewake` Grok ignores) could
  hold Grok's Stop gate for hours.

### Server semantics

- `AgentEventServer` is hand-rolled (Foundation/Network ship no HTTP server):
  one POST + `Content-Length` per connection, 2 MiB cap, loopback peer check
  plus a bound on `127.0.0.1`, constant-time bearer comparison.
- `/v1/agent/event` must answer within the hook's 1 s curl budget; the reply
  body is printed by the hook for the agent (used for deterministic replies).
- `/v1/agent/wait` is the reply channel: a hook parks until the user types a
  message in the notch conversation view (`park`/`reply`), or hangs up. The
  hook turns a text answer into the agent's next turn (exit 2 + stderr).
- Server shutdown answers every parked hook with 204 and cancels incomplete
  pre-authentication connections. Connections, request bytes and wait times are
  bounded; see [audit fixes](project-audit-fixes-2026-10-06.md).

### State and persistence

- `AgentSessionStore` (MainActor) reduces hook events into `AgentSession`
  values, newest first. Finished sessions keep the closed notch lit for
  `finishedHighlightDuration` (6 s); silent sessions are pruned after
  `staleSessionInterval` (30 min). A 60 s prune timer owns both.
- Snapshots persist to `sessions.json` on a serial utility queue with a debounced
  save. Reads check size before allocation; encoding enforces the same 8 MiB
  limit. Cards and preview text are bounded. Normal termination flushes writes.
  Restored sessions come back `isDisconnected` and idle; corrupt predecessors
  remain available for recovery.
- Removed cards live in `hiddenIDs` (with dates) and only resurrect when that
  session starts a new turn.
- `AgentConversationService` owns live streaming text, reachability (can the
  notch send a message to this session right now?), and the parked-reply
  queue; `Assistant/` hosts the screen-question pipeline backend.
- Screen questions run headless with `ATOLL_SUPPRESS_HOOKS=1` so Atoll's own
  agent invocations do not appear as user sessions.

### Bridge gotchas

- The bearer token must never appear in process arguments; it travels via the
  `auth-header` file (`-H @file`). Keep it that way.
- Anything that restarts the server must rewrite `port` before hooks fire
  again; `stop()` deletes the file first, which is what disables the hooks.
- Unit tests run inside the app target with
  `XCTestConfigurationFilePath` set; `AppDelegate` skips all launch
  integrations in that case so a test host cannot take over the real bridge
  directory and delete its port file on exit.

## Verification

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Focused suites that guard these areas:
`FlyoutFrameCalculatorTests`, `SystemHUDPlacementTests`,
`MenuBarClearanceTests`, `TimerHUDTests`, `ClosedHUDSizingTests` (sizing
math); the agents pipeline is
exercised through the regression scripts under `tests/`.
