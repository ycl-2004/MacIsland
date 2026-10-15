# Architecture: window sizing pipeline & agent bridge

Updated 2026-10-10. These are the two subsystems most likely to break in
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
| Closed-HUD demand | `AppDelegate.closedHUDWindowSize()` | connectivity HUD, inline sneak peek, battery HUD state | `CGSize?` — `nil` when no closed HUD is showing |
| Open-tab demand | `AppDelegate.standardWindowSize()` | `coordinator.currentView`, stats/inline-lyrics adjustments | open notch size + shadow padding |
| Window target | `AppDelegate.calculateRequiredNotchSize()` | `max(closedHUDWindowSize(), standardWindowSize())` per axis, plus 24pt width reserved for the recording indicator | the size every window is resized to |
| Per-screen adjustment | `AppDelegate.adjustedSizeForScreen(_:screen:)` | physical-notch vs island (non-notch) screen | adds top bleed (notch screens) or shadow inset ×2 (island mode) |
| Frame application | `AppDelegate.resizeWindow(_:on:to:animated:)` | target size + screen frame | clamped (never wider than the screen), centered, top-anchored `setFrame` |
| SwiftUI content size | `ContentView.dynamicNotchSize` / `DynamicIslandViewModel.calculateDynamicNotchSize()` | same tab/HUD state | the size the SwiftUI layout actually draws at |

`AppDelegate` owns the AppKit frames for all windows (one per screen when
"show on all displays" is on). `ContentView` computes the same HUD math again
for layout. These are two views of one truth, so every HUD size lives in one
tested pure helper that both sides call: `NetworkConnectivityHUDMetrics`,
`TimerHUDMetrics`, `FlyoutFrameCalculator`,
`InlineSneakPeekMetrics`, and `BatteryTemporaryHUDKind.metrics(...)` (which the
battery HUD itself also draws at). A new closed HUD gets its own helper rather
than numbers written into `closedHUDWindowSize()` and `dynamicNotchSize`.

### Screen recording side indicator

`ScreenRecordingManager` observes screen-capture state through the existing CGS
notifications. Detection only publishes recording state and duration; the
per-second duration lives on a separate `RecordingClock` that only the indicator
observes, so the root view does not redraw every second. It does not
write `coordinator.expandingView`, so starting/stopping capture cannot replace or
dismiss another activity. This signal reports a screen watcher and may include
screen sharing, not just a recording saved to disk.

`RecordingHUDLayout` reserves 12pt on each side of the closed content, with a 6pt
red dot in the trailing gutter. `RecordingLiveActivity` wraps the existing content
without changing its height or priority; its dot ignores hit testing. The AppKit
window always budgets those 24pt to avoid resizing during hover transitions.
Hover, click, and scroll-open use the normal navigation path during recording.
Music supplements and camera/microphone indicators remain independent of recording.
The open header retains the dot, with duration in its tooltip and optional Stop
recording in its context menu. Legacy hover-style preferences no longer control
presentation, and the obsolete expanded/inline picker is no longer shown.

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
  `staleSessionInterval` (30 min). A 60 s timer prunes stale cards; cancellable
  one-shot tasks schedule completion expiry and the 250 ms attention window.
- Snapshots persist to `sessions.json` on a serial utility queue with a debounced
  save. `LatestSnapshotWriter` retains one active write and one replaceable latest
  snapshot; automatic saves, explicit saves and termination use the same drain.
  Extra Space uses the same writer and its debounce task captures no document text.
  Reads check size before allocation; encoding enforces the same 8 MiB
  limit. Cards and preview text are bounded. Quit and Restart await the shared asynchronous save gate; a failed or timed-out save cancels exit.
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

- Healthy owner feeds are authoritative for state and content. Identified
  pending requests survive unrelated tool completion. Disconnect and plugin
  overflow expose uncertainty and block ordinary input instead of guessing an
  end. Atoll-owned approvals are scoped to the exact turn and connection epoch.
- Plugin queues and payloads are bounded, with a single deadline-limited owned
  child. Critical overflow is reported as uncertainty. This remains finite,
  best-effort delivery, not a durable event journal. Compatibility profiles and
  old-event limitations are documented in
  [lightweight setup and Agent status](lightweight-setup-and-agent-status.md).

- The bearer token must never appear in process arguments; it travels via the
  `auth-header` file (`-H @file`). Keep it that way.
- Anything that restarts the server must rewrite `port` before hooks fire
  again; `stop()` deletes the file first, which is what disables the hooks.
- Unit tests run inside the app target with
  `XCTestConfigurationFilePath` set; `AppDelegate` skips all launch
  integrations in that case so a test host cannot take over the real bridge
  directory and delete its port file on exit.

## Stats sampling

`StatsManager` owns monitoring policy and UI state on MainActor. It submits
hardware work to `SystemStatsSampler`, an actor that owns Mach buffers, counter
baselines and the lazy CPU sensor subscription. A detached task starts the work
without waiting for the UI executor; the actor serializes the hardware reads.
There is at most one active sample request and one coalesced follow-up per
monitoring session. Stop/restart generation checks and a history revision reject
late results. The sampler commits its collected snapshot only if not cancelled.

Each refresh publishes one `StatsSnapshot` containing the readings and 30-point
histories. The existing metric getters read that snapshot. Monitoring state,
process results and volume capacities remain separate publications. The notch
root no longer subscribes to Stats. Feature management still observes the
monitoring state separately.

Enabled graph preferences request their basic metrics. `StatsDetailSampling`
registers a UUID per visible detail panel, so multiple windows contribute
independently. CPU temperature, frequency, per-core/load/uptime readings and
process scans are requested only by the relevant details. Network interface
details and the 30-second volume-capacity refresh are also demand-gated. The
first network/disk reading establishes a baseline; frequency needs two readings.
Hidden metric histories remain at their last collected values. Transfer totals
count sampled periods; enabling a previously hidden graph starts a new baseline.

The timer is registered on the main run loop in common modes. Its callback
requests background work synchronously, avoiding an extra MainActor task that
can wait behind a nested control-tracking loop. Results are applied when the UI
executor runs; the timer never performs hardware reads itself. See the
[Stats verification report](stats-performance-2026-10-08.md) for measured costs,
regression coverage and field-test limits.

## Shared runtime policy

`AtollRuntimePolicy` holds pure locked/low-power/visibility decisions.
`RuntimePolicyMonitor` receives power and lock notifications and tracks Stats
and Home Calendar surfaces by window identity. Stats sampling stops when disabled or locked and
slows when hidden or in low-power mode. Codex connection refresh uses the same
signals; its event receiver and Timer deadlines are not paused. This is gradual
integration of Stats, Codex refresh and Calendar queries, not a claim that every manager shares the policy.

`FeaturePresetController` previews optional switch changes and stores a small
settings-only undo snapshot. Candidate preference observers invalidate undo
for subsequent manual edits, including value round trips. Shelf and Extra Space
are excluded from the preset; no content removal is part of this transaction.

## Verification

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Focused suites that guard these areas:
`FlyoutFrameCalculatorTests`, `SystemHUDPlacementTests`,
`MenuBarClearanceTests`, `TimerHUDTests`, `ClosedHUDSizingTests` (sizing
math), and `ScreenRecordingPresentationTests` (capture transitions, passive
indicator sizing, privacy coexistence, and native rendering); the agents pipeline is
exercised through the regression scripts under `tests/`.

## Tab and Calendar demand routing

`NotchTabAvailability` is shared by the header, content, coordinator and minimum-width calculation.
Invalid current/remembered/shortcut targets resolve to the first enabled tab in saved order. Color Picker remains a separate utility.
With no enabled tabs, Home is a sentinel that renders Feature Management access rather than hidden feature content.

`CalendarManager` observes the emitted runtime policy and existing settings. No consumer or read access means no periodic query task.
Home consumes the selected date while visible; lock-screen queries require lock plus the calendar widget setting. Reminder activity
consumes a separate current-day snapshot, so browsing another date or hiding Home across midnight cannot change its day.
The existing deadline scheduler stays independent of these display gates. Active refresh is 60 seconds, 120 in low power;
EventKit changes remain throttled and hidden changes are reconciled on next demand. Explicit calendar UI actions can fetch once.
Permission refresh reads existing authorization; the management page and lock-screen widget do not request new access.

Agent pending quantities exclude aggregate status flags; RPC string keys hash the complete identity in a separate namespace.
System Reduce Motion suppresses notch/tab movement, Agent symbol effects and layer pulses, keeping static status information.


## Stability boundaries

`AppTerminationCoordinator` is the only Quit/Restart entry point. AppKit gets
`terminateLater`; Extra Space, Shelf, Agent sessions/drafts and manual Timer state
save asynchronously. Initial content restoration completes before snapshots, so
opening a store lazily during Quit is not mistaken for a new edit. A failure or
ten-second deadline keeps the application open.
The gate retains ownership of unfinished I/O instead of accumulating retries.
Successful restart does not repeat persistence in `applicationWillTerminate`.

`ProcessRunner.capture` drains stdout/stderr concurrently under byte and time
budgets; inherited pipes have a bounded EOF grace. `captureBlocking` is reserved
for serial worker queues, never UI callers. Keyboard backlight reads and writes
are coalesced on one worker. AudioTap control belongs to its serial audio queue;
render callbacks read the immutable bridge and C++ atomic levels, while display
magnitudes and the display timer belong to MainActor. The tap and its timer run
only while a waveform view is drawing (`WaveformDemand`); the last view to stop
ends capture after a five-second grace, so paused music keeps nothing running.

`CodexRPCClient` sends JSONL frames, WebSocket frames, upgrade requests and pongs
through `CodexPipeWriter`. DispatchIO writes asynchronously; a FIFO admits at most
64 frames / 1 MiB, with 512 KiB per complete serialized frame and at most 64 pending
RPC requests. Request timeout/cancellation removes an unstarted frame; if its write
is active, the client closes the channel with `.stop` and disconnects because the
frame may be partial. Reply/notification writes also have a twelve-second deadline.
Delivery is still uncertain after a lost acknowledgement; prompts are never resent.
The channel owns a separate close-on-exec descriptor until its cleanup handler.
See [backpressure fixes](background-backpressure-fixes-2026-10-10.md) for tests and
the DispatchIO/file-descriptor references.

`ServiceRetryPolicy` gives Now Playing and AgentBridge six exponentially spaced
retries (1, 2, 4, 8, 16, 30 seconds), resetting only after a stable minute.
Once Now Playing's round runs out it stays unavailable until a system wake or a
playback command opens one new bounded round; it never retries forever.
Generation checks drop stale replies and stop cancels retry work. Now Playing is
launched through `AtollProcessSupervisor`, which watches its parent with kqueue
and terminates/reaps only its own child. Bridge discovery writes are protected by
an interprocess lock and owner token; an older instance cannot erase a newer
instance's port or credentials.

Native system HUDs coexist with Atoll's HUDs. `SystemOSDManager` never pauses,
launches or polls OSDUIHelper. The former OSD guardian is no longer built into the
application; its fixture regression remains as historical coverage. Private media,
brightness and lock-screen integrations remain optional and need testing on each
supported OS/hardware combination.

`RecoveryFile` serializes bounded private JSON snapshots and preserves unreadable
predecessors. Saving stays refused until a read succeeds; Agent drafts and Timer
read a failed file again before the next save or Quit, so a repaired file is
merged rather than written over. Unsent Agent drafts (64 drafts, 64 KiB each,
1 MiB text total) survive restart; a delivered draft frees its slot. Manual timers retain their absolute deadline or paused duration; already
expired timers are cleared without replaying an alarm. External Clock timers stay
owned by Clock. These snapshots and `.previous` files are recovery aids, not a
versioned backup service.

`AtollDiagnostics` unifies subsystem names, includes historical names during
export, and records bounded fixed-site error counters. Dynamic log messages are
private; errors/warnings survive the Release detail-log setting. `BuildInfo.json`
records commit, dirty state, source/dependency hashes, configuration, SDK and Xcode.
The build phase runs each build. Binary SHA-256 belongs in the verification receipt.

`Tools/verify-stability.py` builds with locked dependencies and runs unit tests in
a copied app with a unique bundle identifier. It also runs synthetic Agent,
plugin and process fixtures, without launching installed agents. Optional address
and thread sanitizer modes share the same isolation. CI pins Xcode 26.3 on
macos-26 and runs this runner plus Release compilation. Toolchain upgrades are
explicit edits, followed by the same suite. The current machine's Xcode 27 run is
separate evidence from hosted CI.

For field acceptance and recovery paths, see
[the stability fixes and debugging guide](stability-fixes-2026-10-10.md).
