# ADR-002: Keep system processes outside Atoll lifecycle ownership

Status: implemented locally, field acceptance pending. Date: 2026-10-10.

The long-term stability review found that a recovery helper cannot guarantee
restoring a paused macOS process when both Atoll and the helper are killed.
ADR-001 reduced that risk but did not eliminate it. For the requested stability
fixes, native HUD coexistence is the default. This changes the visual behavior:
macOS may show its own HUD alongside Atoll. Atoll no longer sends SIGSTOP to,
launches or polls OSDUIHelper. No suppression opt-in is shipped in this change.
The optional preference question received no reply before implementation; this
choice was communicated as the recommended stability-first assumption.

Atoll may supervise processes it starts. Now Playing's Perl adapter runs through
a small bundled supervisor that watches its Atoll parent with kqueue, sends
TERM then KILL to its own child, and reaps it. It never finds targets by process
name. Simultaneous SIGKILL of supervisor and child-owner logic remains outside
any userspace guarantee; this can leave an Atoll-owned adapter, but cannot freeze
a system HUD. Parent kill, supervisor TERM and normal child exit are exercised
using test-created Python/sleep processes only.

Quit and Restart share an asynchronous save gate. AppKit defers termination until
content saves complete. Errors/deadlines keep content open; ongoing disk operations
retain a single gate slot. Unsent Agent drafts and manual Timer state join existing
Extra Space/Shelf/session persistence. No database migration or broad service
rewrite is needed. The tradeoff is that an unavailable disk can prevent graceful
quit until the user exports/recoveries their content or chooses an OS-level force
quit; silently discarding edits is no longer the default.

Agent bridge discovery is an owner lease under an interprocess file lock. An old
instance cannot remove replacement credentials. This protects discovery handoff;
it does not turn two independently launched full Atoll instances into a supported
multi-writer editing mode.

Private APIs remain optional capability-dependent integrations. A passing unit
suite does not establish compatibility with every display, audio device or OS.
Use the [stability guide](../stability-fixes-2026-10-10.md) to accept a specific
Release binary on the supported hardware and OS set.

References: [AppKit deferred termination](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply),
[Apple kqueue manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html).
