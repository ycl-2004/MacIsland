# ADR-001: Own system HUD suppression through a recovery helper

Status: accepted for this local build. Date: 2026-10-06.

Atoll replaces the native volume/brightness HUD by pausing OSDUIHelper. A
termination callback alone cannot recover from SIGKILL or a crash. The optional
product choice was full replacement with recovery versus coexisting HUDs; the
recommended full-replacement behavior was retained after no contrary preference
arrived during implementation.

A small C executable, bundled and signed as `AtollOSDGuardian`, owns the pause.
It checks the target's executable name, uid and birth time, records each lease,
and restores only matching processes. It watches Atoll's exit with
`kqueue`/`EVFILT_PROC`/`NOTE_EXIT`, and also restores on command-pipe EOF. It waits
for events without a recurring timer. A missing or failed helper never triggers
an unprotected direct SIGSTOP. Closing one helper is serialized before creating
its replacement, preventing an old release from undoing a new pause.

The helper is a separate executable: it does not initialize SwiftUI, Agent
integrations, settings, or the production app's services. The build phase uses
the app's architectures and signs it before the outer app. No new package or
minimum OS increase is needed.

The existing watcher still discovers new OSDUIHelper processes in-process and
backs off while stable; sleep stops it. This decision fixes crash recovery, not
all private-API compatibility or watcher energy concerns. Deliberately killing
the guardian independently, killing both processes together, and future macOS
HUD changes remain external failure cases. Hardware/OS acceptance is required.

The regression compiles the helper with `ATOLL_GUARDIAN_TEST`, which permits
only owned `sleep` fixtures. Normal parent exit and SIGKILL both restored the
fixture. Tests never send signals to the real OSDUIHelper.

Alternatives: accepting duplicate HUDs removes process suppression entirely but
changes the selected replacement behavior. A shell polling loop adds recurring
wakes and subprocesses. Signal handlers in Atoll cannot handle SIGKILL.

Primary reference: [Apple kqueue manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html).
