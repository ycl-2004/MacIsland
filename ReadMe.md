<h1 align="center">Atoll</h1>

<p align="center">
  <strong>A focused macOS notch HUD tailored for developers and AI agent workflows.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/build-1.0.0%20(YC__Island__v1)-111111" alt="Build: 1.0.0 (YC_Island_v1)">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-111111?logo=apple&logoColor=white" alt="macOS 14.0 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" alt="Built with SwiftUI and AppKit">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-111111" alt="GPL-3.0 License"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a>
  ·
  <a href="#why-atoll">Why Atoll</a>
  ·
  <a href="#features">Features</a>
  ·
  <a href="#how-it-works">How it works</a>
  ·
  <a href="#privacy--security">Privacy & Security</a>
  ·
  <a href="#build-from-source">Build from source</a>
  ·
  <a href="#credits">Credits</a>
  ·
  <a href="LICENSE">License</a>
  ·
  <a href="README.zh-TW.md">繁體中文</a>
</p>

Atoll transforms the MacBook notch into an unobtrusive, interactive command cockpit. It remains completely invisible during deep work, expanding smoothly into a responsive native SwiftUI surface whenever summoned by cursor proximity, gesture, or global shortcut.

This edition is YC's personal customized build (`YC_Island_v1`). It introduces first-class hardware notch integration for AI coding agents (**Claude Code**, **Codex**, **Antigravity**, **Pi**, **OpenCode**, and **Grok Build**), strips away legacy background bloat, and refines core daily utilities—including multi-source media controls, dynamic sweep-synced lyrics, lock screen widgets, an interactive ruler timer, and low-overhead hardware telemetry.

> **Source-first personal build.** This repository is YC's personal daily driver build, maintained for private development workflows on Apple Silicon MacBooks. It is not distributed as a pre-compiled signed binary; build and run it directly in Xcode. Derived from [Atoll by Ebullioscopic](https://github.com/Ebullioscopic/Atoll) and [boring.notch](https://github.com/TheBoredTeam/boring.notch) under the GNU General Public License v3.0.

---

## Quick start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ycl-2004/Atoll.git
   cd Atoll
   ```
2. **Open in Xcode:**
   ```bash
   open DynamicIsland.xcodeproj
   ```
3. Set the run destination to **My Mac** and press **⌘R** to build and run.
4. **Grant permissions on first launch:**
   - **Accessibility**: Required for positioning the notch window over system spaces and capturing global trigger shortcuts.
   - **Screen Recording**: Required for the *Ask About Screen* marquee capture and the screen color loupe.
   - **Music**: Required for Apple Music playback controls and track metadata.
5. Move your pointer near the MacBook notch to open the interface, or press `⌘⇧A` to select any screen region and ask an active AI agent about it.

### System requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15+ (Sequoia).
- **Hardware**: MacBook with a physical display notch (14-inch or 16-inch MacBook Pro, M2/M3 MacBook Air across Apple silicon generations).
- **Toolchain**: Xcode 15.0 or later with Swift 5.9 toolchain.

---

## Why Atoll

- **An AI agent cockpit on your hardware notch.** Instead of burying agent progress in hidden terminal tabs, active sessions from Claude Code, Codex, Antigravity, Pi, OpenCode, and Grok Build surface directly at the top of your display with live status, streaming output, and prompt controls.
- **Instant visual queries with Ask About Screen.** Drag a selection marquee over any part of your display (`⌘⇧A`) and send it directly to an agent session without manually capturing screenshots, saving files, or switching contexts.
- **Stripped of bloat, whisper quiet.** Removed unused clipboard history managers, embedded web terminals, orphaned background daemons, and keep-awake runners. Background work is limited to enabled features; Shelf caches and thumbnail jobs have explicit limits.
- **Polished daily driver utilities.** Seamless media playback for Apple Music, Spotify, TIDAL, YouTube Music, and NetEase; dynamic sweep-highlight lyrics; lock screen widgets; interactive ruler timer; and low-overhead hardware telemetry.
- **Local-first privacy.** All agent communications, terminal conversations, and screen questions operate strictly on-device through local IPC and session files. No telemetry, no accounts, and no intermediate servers.

---

## Features

### 🤖 AI Coding Agent Live Cockpit
- **Live session monitoring**: Real-time cards in the notch tab track active sessions for **Claude Code**, **Codex**, **Antigravity**, **Pi**, **OpenCode**, and **Grok Build**.
- **Notch Live Activity**: Subtle notch status indicators animate when an AI agent is actively executing commands, analyzing code, or running tests.
- **Live terminal conversations**: Read streaming responses and send follow-up prompts or answers directly through the notch drawer.
- **Ask About Screen (`⌘⇧A`)**: Drag-select any window or screen area to immediately dispatch the image crop and your query to an active agent.

### 🎵 Media & Audio HUD
- **Universal player integration**: Native playback controls and metadata for Apple Music, Spotify, TIDAL, YouTube Music, Cider, and NetEase Cloud Music.
- **Real-time audio visualizer**: Hardware-accelerated C++ CoreAudio process taps deliver responsive waveform visualizers synchronized with playback.
- **Dynamic sweep lyrics**: Time-synchronized lyrics with fluid sweep highlights following the sung vocals in real time, plus an expanded lyrics view on the lock screen.
- **Trackpad scrub gestures**: Horizontal two-finger swipes on the notch seek tracks forward/backward (±10s) or skip tracks with native haptic clicks.

### 🔒 Lock Screen Widgets & System HUDs
- **Lock screen music player**: High-resolution album artwork, interactive volume slider, and side-by-side synchronized lyrics.
- **Modular lock screen widgets**: Live countdown timer, local weather via Open-Meteo, battery percentage, and connected Bluetooth device levels.
- **Notch-aligned system HUDs**: Sleek replacements for standard macOS overlays, covering volume, display brightness, keyboard backlight, webcam, microphone, and screen recording.

### ⚡ System Insights & Developer Utilities
- **Hardware telemetry**: Low-overhead SMC and IOReport sensors displaying per-core CPU usage, temperature, GPU load, unified memory pressure, network throughput, and disk I/O.
- **Interactive ruler timer**: Scrollable ruler timer for quick Pomodoro intervals, countdowns, and stopwatch tracking.
- **Centred timer HUD**: The timer icon and countdown sit left of the physical notch; Pause/Resume, Restart and Stop sit right, in equal-width wings. Seconds, minutes, hours and signed overtime share a stable width reservation. Restart resets an Atoll timer to its original duration; mirrored Clock timers must be restarted in Clock. The housing stays fixed even beside long app menus, which can overlap the HUD. Timer names remain available in the expanded panel and tooltip, or through the explicit name-display setting.
- **Screen color picker**: Fast color sampler with a 10× pixel-level loupe and one-click HEX clipboard copying.
- **Shelf dock**: Drag files, text, and links onto the notch to stage them. Turning Shelf off hides it and preserves its contents. Clear is a separate action; original files and active handoffs are protected. See [Shelf resource lifecycle](docs/shelf-lifecycle.md).
- **Calendar glance**: Quick agenda view for upcoming calendar events.
- **Extra Space**: Enable it in Settings → Utilities → Extra Space to add a main tab with one continuous, scrollable text area. Double-click the text area, or click Edit or Paste, to change text; Cmd+S or Save finishes editing. The close swipe saves and closes in reading mode. Cmd+F opens native find; Export saves a plain-text copy. Changes persist locally across restarts. Turning the feature off hides the tab and keeps its contents. See [Extra Space](docs/extra-space.md).

---

## How it works

- **Notch tracking and presentation**: Atoll monitors cursor proximity and gesture events along the display bezel to expand and collapse the SwiftUI canvas without stealing active window focus.
- **Local agent observation**: `AgentBridge` and `AgentSessionStore` monitor local session files, logs, and language server endpoints from Claude Code, Codex, Antigravity, Pi, OpenCode, and Grok Build, decoding streaming chunks without external network hops.
- **Screen question pipeline**: `ScreenQuestionManager` captures a drag-selected screen bounding box via `CGWindowListCreateImage`, attaches it as context, and dispatches the query directly to the active agent conversation service.

---

## Privacy & Security

- **Strictly local-first**: There are no accounts, no usage telemetry, no analytics beacons, and no crash reporting services.
- **Agent IPC is on-device**: All interactions with Claude Code, Codex, Antigravity, Pi, OpenCode, and Grok Build communicate through local process files and local IPC sockets. No code, prompts, or terminal outputs are routed through any intermediate server.
- **Explicit network boundaries**: Network requests are strictly limited to user-enabled features: Open-Meteo for local weather forecasts and public lyric providers (LRCLIB / NetEase Cloud Music) when media playback is active.
- **Screen capture scope**: Screen capture is strictly invoked on-demand when triggering *Ask About Screen* or the screen color loupe; Atoll never captures or records screen contents in the background.

---

## FAQ

<details>
<summary>Why does Atoll need Accessibility and Screen Recording permissions?</summary>

**Accessibility** is required to position the notch overlay window across system spaces, track cursor hover near the screen cutout, and register global hotkeys.

**Screen Recording** is requested strictly for two user-triggered features: capturing the selected rectangle when using *Ask About Screen* (`⌘⇧A`), and magnifying pixels under the cursor in the screen color picker. Atoll never captures or stores background screen data.

</details>

<details>
<summary>How does Ask About Screen connect to my terminal agents?</summary>

When you drag out a marquee selection on your screen, Atoll captures the image region and pairs it with your prompt. It communicates with your active Claude Code, Codex, or Antigravity session through local session bridges, routing the image and text directly into the selected agent's context.

</details>

<details>
<summary>Which music players are supported?</summary>

Atoll supports Apple Music, Spotify, TIDAL, YouTube Music, Cider, and NetEase Cloud Music. Now Playing metadata is observed automatically, and playback commands (play/pause, seek, skip, favorite) are routed through each player's native scripting bridge or local API.

</details>

<details>
<summary>How do I completely uninstall Atoll and reset preferences?</summary>

Quit Atoll from the menu bar or notch settings, then remove `Atoll.app` from `/Applications`. To remove saved preferences:

```bash
defaults delete com.ebullioscopic.DynamicIsland
```

You can revoke permissions in **System Settings → Privacy & Security → Accessibility / Screen Recording**.

</details>

---

## Build from source

<details>
<summary>Requirements, build commands, and test verification</summary>

### Requirements
- macOS 14.0 or later.
- Xcode 15.0 or later.
- Apple Silicon Mac with physical notch.

### Command-line build verification
To verify a build without using a developer signing identity:

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### Running unit tests
To execute the unit test suites:

```bash
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:DynamicIslandTests
```

The repository tracks source files, assets, test fixtures, and shared workspace configurations while excluding generated DerivedData, local build artifacts, and developer Team IDs.

</details>

---

## Project layout

| Directory / File | Description |
| :--- | :--- |
| `DynamicIsland/` | Main application source, AppKit window controllers, and SwiftUI views |
| `DynamicIsland/components/Agents/` | AI Agent session cards, stream viewer, and screen question card |
| `DynamicIsland/managers/Agents/` | Agent session registry, transcript parsers, and local IPC bridge |
| `DynamicIsland/components/LockScreen/` | Lock screen widgets (Music, Weather, Timer, Bluetooth) |
| `DynamicIsland/components/Music/` | Audio player integrations, lyrics synchronizer, and waveform visualizer |
| `DynamicIsland/components/Notch/` | Dynamic Island notch window, tabs, header, and animations |
| `DynamicIsland/components/Settings/` | Preferences views, layout configuration, and shortcut recorders |
| `DynamicIsland/components/Shelf/` | Drag-and-drop temporary staging shelf |
| `DynamicIsland/components/Stats/` | SMC and IOReport hardware telemetry sensors |
| `DynamicIsland/components/Timer/` | Interactive ruler timer and countdown components |
| `DynamicIslandTests/` | Unit tests for state managers, lyrics parsing, and session handlers |
| `DynamicIslandUITests/` | UI automation tests |
| `tests/` | Standalone regression scripts and verification helpers |

---

## Versioning and releases

- **Release Name**: `YC_Island_v1` (defined in `DynamicIsland/strings/constants.swift`).
- **Marketing Version**: `1.0.0` (build 1637) in `DynamicIsland.xcodeproj`.
- **Branch**: `feat/agents`.
- This is a personal source-first repository. Versions mark milestones in personal workflow customization.

---

## Credits & Homage (致敬)

Atoll (YC Edition) is crafted with gratitude and pays homage to the pioneering open-source projects that built the foundation:

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) by **Ebullioscopic** — The modern, highly configurable macOS notch foundation.
- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) — The pioneer project that originated the macOS Dynamic Island concept and interaction patterns.
- [**Stats**](https://github.com/exelban/stats) by **exelban** — The foundational SMC and IOReport system monitoring implementation.
- [**Alcove**](https://tryalcove.com) — Conceptual inspiration for the lock screen widget layout.
- [**Open-Meteo**](https://open-meteo.com) — Free, privacy-friendly weather APIs.
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) by **Lakr233** — Window management techniques for lock screen overlays.
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) — Real-time audio waveform sampling.
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) — Battery HUD design inspiration.

---

## Known limitations

- **Physical notch requirement**: Layouts and hit-testing are calibrated for Apple Silicon MacBooks with display cutouts (14" / 16" MBP, M2/M3 MacBook Air).
- **Supported agent environments**: Agent live tracking currently supports Claude Code, Codex, Antigravity, Pi, OpenCode, and Grok Build. Pi and OpenCode connect through a small Atoll plugin file instead of hooks; other CLI tools require manual bridging.
- **Screen Recording prompt**: The first use of *Ask About Screen* requires macOS Screen Recording approval followed by an application restart.

---

## License

Atoll is free software released under the [GNU General Public License v3.0](LICENSE).

Refer to [NOTICE](NOTICE), [COPYRIGHT_ASSETS](COPYRIGHT_ASSETS), and [TRADEMARKS](TRADEMARKS) for asset licenses and trademark disclaimers.

Reliability limits, recovery and verification: [2026-10-06 audit fixes](docs/project-audit-fixes-2026-10-06.md).

Lightweight setup, optional settings preview/undo, Extra Space shortcut and
Agent status semantics: [feature management guide](docs/lightweight-setup-and-agent-status.md).
