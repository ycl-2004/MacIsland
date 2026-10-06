# Atoll audit fixes — 2026-10-06

This follows the [original audit](project-audit-2026-10-06.md). Its original
measurements are retained. These changes address F01–F14 while preserving the
existing native tabs, content, macOS 14.6 minimum and unrelated worktree edits.

## Changes and limits

| Finding | Implemented correction | Evidence / acceptance boundary |
| --- | --- | --- |
| F01 | Agent snapshots load, encode and write on a serial utility queue. Size is checked before reading. Up to 60 recent cards, 40 messages and 64 KiB of message text per card; metadata/ids are bounded. JSON stays within 8 MiB. A damaged predecessor is retained for recovery. | Synthetic 1/14/60-card source probes reload every card; content tests cover large Unicode history and the card limit. This is preview cache, not the canonical transcript archive. |
| F02 | Music JSON lines assemble bytes until newline; partial UTF-8 is never decoded prematurely. Oversized lines are discarded through their newline, with a 4 MiB line limit. | Every split boundary in a Chinese/emoji fixture decodes correctly. |
| F03 | One locked pipe-read waiter completes once on data, EOF or close; cancellation closes it. | Empty-stream cancellation completes without continuation warnings. |
| F04 | A separate native guardian owns pauses and restores on parent exit or pipe EOF, checking uid/name/birth time. Restoration no longer kills/reloads the system HUD service. | Normal-exit and SIGKILL synthetic fixtures pass. Real system HUD, sleep/wake and OS compatibility require manual acceptance. See [ADR](decisions/001-system-hud-recovery.md). |
| F05 | Shared process runner drains stdout/stderr concurrently, caps retained output, cancels timers, and escalates TERM to KILL for its own child after 250 ms. Pipe EOF after child exit has a one-second drain grace. Log export, zip, Stats and Bluetooth collectors use it; the IORegistry fallback is off-main. | Large-output, deadline and cancellation regressions pass. Blocking legacy collectors are restricted to utility queues. Kernel/filesystem I/O cannot be forcibly cancelled by this runner. |
| F06 | Downloads retains its settings subscription; existing monitoring and speed generations retain stale-result protection. | Combine lifetime control and PartialDownload regressions; real folder permissions/toggling need manual acceptance. |
| F07 | Extra Space rejects changes above 5 MiB, checks file size before loading, deduplicates repeated saves, retains one prior saved revision, and exposes recovery/reveal in Settings. Files/directories are private. | Oversized load/edit, save ordering, permissions and explicit recovery tests. All original 13 edit/gesture/layout tests still pass. |
| F08 | Shelf loads/saves off-main and coalesces writes. New content: 200 items, 1 MiB per text item/4 MiB total, 50 providers per drop/100 queued. Copies: 100 MiB per import, 250 MiB owned storage; archive work reserves capacity and snapshots bounded regular files before zip. | Original 26 Shelf tests plus copy/archive regressions. Existing oversized stores are preserved, not silently truncated. Finder references do not copy file contents. Symbolic-link or special-file attachments must use ordinary Finder references rather than copied/archive representations. |
| F09 | Agent server caps connections at 32, retained request bytes at 16 MiB total/2 MiB per request, headers at 16 KiB; pre-authentication requests expire after 5 s and parked replies after 8 h. Stop releases pre-auth state and answers parked replies. Focus buffers are capped at 1 MiB; conversation sidecars prune removed cards, and new drafts have byte/count budgets. Weather requests coalesce, have an 8 s location deadline, and use 30–300 s failure backoff. | Synthetic local server request/timeout/stop tests. Real location and weather failures require manual acceptance. Unsent drafts are bounded but remain in-memory and do not survive app restart. |
| F10 | UI/audio gain uses a lock-free C++ atomic scalar with relaxed access. Diagnostic peak scanning/logging compiles only in Debug. | Audio and per-app volume regressions; realtime hardware stress and Thread Sanitizer not run. |
| F11 | ATS permits local networking rather than arbitrary remote loads; content uses 0700 directories/0600 files. Camera/microphone monitoring follows enabled flags; Bluetooth battery access is lazy. | Build/permission fixtures. The application is not sandboxed; local saving is not encryption or same-user process isolation. |
| F12 | Both restart entry points flush content and share launch handling. Failed saving, failed launch, a terminated replacement or a same-process response keeps the current app open. Extra Space editing pauses during handoff. | Compiled and inspected; no production restart was invoked by QA. |
| F13 | Thumbnail keys include file modification time, size and identity; bookmark/rename updates invalidate only affected URLs. Cache stays at 48 entries/8 MiB, with two active requests, 256 pending keys and 32 consumers per key. | Existing thumbnail/lifetime regressions and build. Cache bytes do not measure total Quick Look or process memory. |
| F14 | Stats ignores old/cancelled results; optional app services are lazy and native test services/content directories are isolated. Bluetooth polling stops when no dependent feature is enabled. Icon imports decode bounded 512 px thumbnails off-main; sound imports are bounded and atomic before old copies are removed. Unused open-meteo package reference removed. | Native startup/path tests, sound regressions and builds. Existing Swift 5 concurrency/deprecation warnings remain elsewhere. |

Extra Space keeps up to 200 undo groups for small documents. Larger documents
reduce that count using a conservative 16 MiB whole-document history allowance;
when the allowance shrinks, earlier undo history is released before recording
the new edit. The new paste remains undoable. This limits retained editing
history; it is not a total memory guarantee for AppKit text layout.

Recovery keeps `content.txt.previous` and, after explicit recovery, the displaced
primary as `content.txt.recovery`. An existing recovery copy blocks replacement
of that copy. Export/move it deliberately before repeating recovery. File read
failures never initialize an empty writable scratchpad.

## Verification

- Broad final affected native regression run: 170 tests, 0 failures.
- Storage isolation/archive targeted run: 58 tests, 0 failures. The final
  same-text recovery correction then passed 24 content/editor tests, 0 failures.
  All original Extra Space and Shelf tests remain covered.
- Standalone Python regression suite: 7 tests passed after adding its new file-helper dependency.
- Exact-source music/session probes: split Unicode survives; cancelled reader
  finishes; 1/14/60 cards all reload. Measured save enqueue times were about
  0.014/0.023/0.070 ms, compared with the original synchronous 14/43/180 ms fixture.
  The new enqueue measurement excludes background encoding/disk time and the
  termination barrier; the snapshot sizes are also smaller.
- Four guardian cases pass: normal parent exit, parent SIGKILL, guardian SIGTERM,
  and preserving a fixture already stopped by another owner. Only temporary
  sleep processes are signalled.
- Final Release build passed. The installed app and guardian match the build
  hashes and pass strict signature verification; the signature requirement is
  unchanged. Installation used normal app termination and retained the prior
  bundle at `Build/InstalledBackups/20261006-153307/Atoll.app`. No automatic
  production relaunch occurred. See [verification receipt](audit/2026-10-06-fixes/verification.json).

Failures corrected during implementation: missing Combine import; duplicate
runtime helper; standalone sound harness missing the file helper dependency;
a mistyped signing fingerprint. No user data was replaced by these checks.

The prior audit and this work did not perform a 24–72 h soak, real Agent CLI
integration, actual clipboard transfers to other people, hardware audio/BT/OSD
stress, network-volume failure simulation, or a full Swift 6 migration. Test
hosts may emit system linkd/XPC diagnostics even when tests pass.

## Performance fit and development storage

This design suits an always-running lightweight notch utility and bounded
scratchpad. It is not evidence for sustained high throughput or large document
editing. Typical small notes, bounded caches and event-driven service lifetimes
are the intended workload. Large paragraphs can still make native text layout
expensive; private system integrations remain OS-dependent.

Before claiming long-term reliability, run the original audit's 24–72 h soak
matrix on the user's actual enabled features. Track main/helper footprint,
CPU time, file descriptors, retained content, sleep/wake behavior and UI hitches.
The memory warning threshold is not a process memory cap.

`python3 Tools/report-build-cache.py` is read-only by default. It reports old
complete test results and installation backups under this repo's `Build/`,
retaining the newest three results/two backups. `--apply` is an explicit opt-in
for pruning only those candidates. Current builds, package cache, git data and
application content are excluded. No bulk cache pruning was performed this run.
